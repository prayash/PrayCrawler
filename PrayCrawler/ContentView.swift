//
//  ContentView.swift
//  PrayCrawler
//
//  Created by Prayash Thapa on 12/15/23.
//

import SwiftUI

struct ContentView: View {
    @StateObject var crawler = Crawler()
    @State var loading = false
    
    var body: some View {
        List {
            ForEach(Array(crawler.state.keys.sorted(by: { $0.absoluteString < $1.absoluteString })), id: \.self) { url in
                HStack {
                    Text(url.absoluteString)
                    Text(crawler.state[url]!.title)
                }
                
            }
        }
        .overlay(
            Text("\(crawler.state.count) items")
                .padding()
                .background(Color.black.opacity(0.8))
            
        )
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { // [crawler] in
            do {
                let crawler = Crawler()
                let start = Date()
                try await crawler.crawl(url: URL(string: "https://prayash.io")!, numberOfWorkers: 8)
                let end = Date()
                
                print(end.timeIntervalSince(start))
            } catch {
                print(error)
            }
        }
    }
}

#Preview {
    ContentView()
}
