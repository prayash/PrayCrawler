//
//  ContentView.swift
//  PrayCrawler
//
//  Created by Prayash Thapa on 12/15/23.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @State var crawlerResults: [URL: Page] = [:]
    @State var isLoading = true
    @State var isCancelled = false
    @State var targetURLString = "https://prayash.io"
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Crawling \(targetURLString)...")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Button("Cancel") {
                    isCancelled = true
                    print("[prt] : User pressed cancel.")
                }
            }.padding(.horizontal)
            
            List {
                let dataSource = Array(crawlerResults.keys.sorted { $0.absoluteString < $1.absoluteString })
                
                ForEach(dataSource, id: \.self) { url in
                    HStack {
                        Text(url.absoluteString)
                            .bold()
                        
                        Text(crawlerResults[url]!.title)
                            .foregroundStyle(.secondary)
                    }.padding(2)
                }
            }
            .animation(.default, value: crawlerResults.keys)
            .listRowSeparator(.visible)
            .overlay(
                Text("\(crawlerResults.count) items")
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .opacity(isLoading ? 1.0 : 0.0)
                    .cornerRadius(5)
                
            )
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: isCancelled) {
                guard !isCancelled else { return }
                
                /// Consumer-side cancellation.
                await withTaskCancellationHandler {
                    do {
                        let start = Date()
                        let crawlerStream = crawl(url: URL(string: targetURLString)!, numberOfWorkers: 8)
                        
                        for try await page in crawlerStream {
                            self.add(page)
                        }
                        
                        let end = Date()
                        print("[prt] : Done crawling \(self.crawlerResults.count) items! Time elapsed is \(end.timeIntervalSince(start))s.")
                        isLoading = false
                    } catch {
                        print(error)
                    }
                } onCancel: {
                    print("[prt] : The consumer task was cancelled.")
                }
            }
        }
        .padding()
    }
    
    func add(_ page: Page) {
        crawlerResults[page.url] = page
    }
}

#Preview {
    ContentView()
}
