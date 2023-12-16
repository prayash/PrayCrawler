//
//  Crawler.swift
//  PrayCrawler
//
//  Created by Prayash Thapa on 12/15/23.
//

import Foundation

actor Queue<T: Hashable> {
    private var storage: Set<T> = []
    private var inProgress: Set<T> = []
    
    func dequeue() -> T? {
        guard let result = storage.popFirst() else { return nil }
        
        inProgress.insert(result)
        return result
    }
    
    func finish(_ item: T) {
        inProgress.remove(item)
    }
    
    func add(items: any Sequence<T>) {
        storage.formUnion(items)
    }
    
    var isDone: Bool {
        storage.isEmpty && inProgress.isEmpty
    }
}

@MainActor
final class Crawler: ObservableObject {
    @Published var state: [URL: Page] = [:]
    
    func add(_ page: Page) {
        state[page.url] = page
    }
    
    func seenURLs() -> Set<URL> {
        Set(state.keys)
    }
    
    func crawl(url: URL, numberOfWorkers: Int = 4) async throws {
        let basePrefix = url.absoluteString
        let queue = Queue<URL>.init()
        await queue.add(items: [url])
        
        /// We HAVE to wait until all child tasks are done.
        /// We know after this method exits, parallelism will end.
        /// This is what it means to have structured concurrency.
        /// Task group will keep running as long as child tasks are running.
        /// We need to react to all child tasks, otherwise the top-level task will stay suspended!
        /// This is NOT parallelism in CPU workload, but rather I/O tasks.
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<numberOfWorkers {
                group.addTask {
                    var numberOfJobs = 0
                    
                    while await !queue.isDone { // This is TOO busy!
                        defer { numberOfJobs += 1 }
                        guard let job = await queue.dequeue() else {
                            try await Task.sleep(nanoseconds: 1000) // ew!
                            continue
                        }
                        
                        let page = try await URLSession.shared.page(from: job)
                        let seen = await self.seenURLs()
                        let newURLs = page.outgoingLinks.filter { url in
                            url.absoluteString.hasPrefix(basePrefix) && !seen.contains(url)
                        }
                        
                        await queue.add(items: newURLs)
                        await self.add(page)
                        await queue.finish(page.url)
                    }
                    
                    print("Worker \(i) did \(numberOfJobs) jobs")
                }
            }
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

