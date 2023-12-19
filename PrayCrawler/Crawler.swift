//
//  Crawler.swift
//  PrayCrawler
//
//  Created by Prayash Thapa on 12/15/23.
//

import Foundation

/// Actor-based queue for tracking crawler work.
actor Queue<T: Hashable> {
    private var storage: Set<T> = []
    private var inProgress: Set<T> = []
    private var pendingDequeues: [() -> Void] = []
    private var seen: Set<T> = []
    
    func dequeue() async -> T? {
        guard !Task.isCancelled else { return nil }
        
        if let result = storage.popFirst() {
            inProgress.insert(result)
            return result
        } else {
            if isDone {
                return nil
            }
            
            // print("[prt] : No items – suspending...")
            /// A neat use case for continuations is for manual suspensions
            /// and not just retrofitting traditional completion-handler
            /// based APIs for the async world.
            await withCheckedContinuation { continuation in
                pendingDequeues.append(continuation.resume)
            }
            
            return await dequeue()
        }
    }
    
    func finish(_ item: T) {
        inProgress.remove(item)
        if isDone {
            flushPendingDequeues()
        }
    }
    
    func add(items: any Sequence<T>) {
        let trulyNew = items.filter { !seen.contains($0) }
        seen.formUnion(trulyNew)
        storage.formUnion(trulyNew)
        
        flushPendingDequeues()
    }
    
    fileprivate func flushPendingDequeues() {
        for continuation in pendingDequeues {
            continuation()
        }
        
        pendingDequeues.removeAll()
    }
    
    private var isDone: Bool {
        storage.isEmpty && inProgress.isEmpty
    }
}

typealias CrawlerStream = AsyncThrowingStream<Page, Error>

fileprivate func crawlHelper(
    url: URL,
    numberOfWorkers: Int = 4,
    continuation: CrawlerStream.Continuation
) async throws {
        let basePrefix = url.absoluteString
        let queue = Queue<URL>.init()
        await queue.add(items: [url])
        
        /// We HAVE to wait until all child tasks are done.
        /// We know after this method exits, parallelism will end.
        /// This is what it means to have structured concurrency.
        /// Task group will keep running as long as child tasks are running.
        /// We need to react to all child tasks, otherwise the top-level task will stay suspended!
        /// This is NOT parallelism in CPU workload, but rather I/O tasks.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<numberOfWorkers {
                group.addTask {
                    var numberOfJobs = 0
                    
                    while let job = await queue.dequeue() {
                        defer { numberOfJobs += 1 }
                        
                        let page = try await URLSession.shared.page(from: job)
                        try await Task.sleep(nanoseconds: NSEC_PER_SEC * 1) // REMOVE!!
                        let newURLs = page.outgoingLinks.filter { url in
                            url.absoluteString.hasPrefix(basePrefix)
                        }
                        
                        await queue.add(items: newURLs)
                        continuation.yield(page)
                        await queue.finish(page.url)
                    }
                    
                    print("[prt] : Worker \(i) did \(numberOfJobs) jobs")
                }
            }
            
            do {
                /// Iterate over the results of the child tasks (which is either Void or throws)
                for try await _ in group {}
            } catch {
                print("[prt] : Worker error \(error)")
                await queue.flushPendingDequeues()
                throw error
            }
        }
        
        print("[prt] : All crawler child tasks have been completed.")
}

func crawl(url: URL, numberOfWorkers: Int = 4) -> CrawlerStream {
    return CrawlerStream { continuation in
        let producerTask = Task(priority: .userInitiated) {
            do {
                try await crawlHelper(
                    url: url,
                    numberOfWorkers: numberOfWorkers,
                    continuation: continuation
                )
                
                continuation.finish(throwing: nil)
            } catch {
                print("[prt] : TaskGroup finished with an error: \(error)")
                continuation.finish(throwing: error)
            }
        }
        
        continuation.onTermination = { @Sendable _ in
            print("[prt] : The producer task was terminated as a result of consumer task cancellation.")
            producerTask.cancel()
        }
    }
}

extension URLSession {
    func page(from url: URL) async throws -> Page {
        let (data, _) = try await data(from: url)
        let doc = try XMLDocument(data: data, options: .documentTidyHTML)
        let title = try doc.nodes(forXPath: "//title").first?.stringValue
        let links: [URL] = try doc.nodes(forXPath: "//a[@href]").compactMap { node in
            guard let el = node as? XMLElement else { return nil }
            guard let href = el.attribute(forName: "href")?.stringValue else { return nil }
            return URL(string: href, relativeTo: url)?.simplified
        }
        return Page(url: url, title: title ?? "", outgoingLinks: links)
    }
}

extension URL {
    var simplified: URL {
        var result = absoluteString
        if let i = result.lastIndex(of: "#") {
            result = String(result[..<i])
        }
        if result.last == "/" {
            result.removeLast()
        }
        return URL(string: result)!
    }
}

extension URL: Sendable {}

struct Page {
    var url: URL
    var title: String
    var outgoingLinks: [URL]
}

