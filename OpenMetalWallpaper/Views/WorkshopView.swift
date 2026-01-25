//
//  WorkshopView.swift
//  OpenMetalWallpaper
//
//  Created by laobamac on 2026/1/17.
//

import SwiftUI

struct WorkshopView: View {
    @EnvironmentObject var library: WallpaperLibrary
    @StateObject private var steam = SteamService.shared
    
    @Binding var selectedItem: SteamWorkshopItem?
    
    @State private var items: [SteamWorkshopItem] = []
    @State private var searchText: String = ""
    @State private var selectedType: String = "Video"
    @State private var selectedGenre: String = "all"
    @State private var selectedSort: String = "trend"
    @State private var currentPage: Int = 1
    @State private var isLoading: Bool = false
    @State private var hoverItemId: String? = nil
    
    let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)]
    
    let types = [("视频", "Video"), ("场景", "Scene"), ("网页", "Web")]
    let genres = [("全部", "all"), ("动漫", "Anime"), ("游戏", "Game"), ("风景", "Landscape"), ("科幻", "Sci-Fi"), ("赛博朋克", "Cyberpunk"), ("像素", "Pixel art")]
    let sorts = [("趋势", "trend"), ("最新", "mostrecent"), ("最热", "totaluniquesubscribers")]
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("搜索壁纸...", text: $searchText)
                            .textFieldStyle(.plain)
                            .onSubmit { loadItems(reset: true) }
                        if !searchText.isEmpty {
                            Button(action: { searchText = ""; loadItems(reset: true) }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .frame(maxWidth: 300)
                    
                    Button(action: { loadItems(reset: true) }) {
                        Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundColor(.accentColor)
                    }.buttonStyle(.plain)
                    
                    Spacer()
                    
                    if !steam.isSteamCMDInstalled {
                        Button("安装引擎") { steam.installSteamCMD() }.buttonStyle(.borderedProminent)
                    }
                    Button(action: { loadItems(reset: true) }) {
                        Image(systemName: "arrow.clockwise")
                    }.help("刷新")
                }
                
                HStack {
                    HStack(spacing: 4) {
                        Text("类型:").font(.caption).foregroundColor(.secondary)
                        Picker("", selection: $selectedType) {
                            ForEach(types, id: \.1) { name, tag in Text(name).tag(tag) }
                        }.pickerStyle(.segmented).frame(width: 200)
                    }
                    Spacer().frame(width: 20)
                    HStack(spacing: 4) {
                        Text("内容:").font(.caption).foregroundColor(.secondary)
                        Picker("", selection: $selectedGenre) {
                            ForEach(genres, id: \.1) { name, tag in Text(name).tag(tag) }
                        }.pickerStyle(.menu).frame(width: 100)
                    }
                    Spacer().frame(width: 20)
                    HStack(spacing: 4) {
                        Text("排序:").font(.caption).foregroundColor(.secondary)
                        Picker("", selection: $selectedSort) {
                            ForEach(sorts, id: \.1) { name, tag in Text(name).tag(tag) }
                        }.pickerStyle(.menu).frame(width: 100)
                    }
                    Spacer()
                }
            }
            .padding()
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
            .zIndex(1)
            
            ZStack {
                if items.isEmpty && !isLoading {
                    VStack {
                        Image(systemName: "icloud.slash").font(.largeTitle).foregroundColor(.gray)
                        Text("暂无内容").foregroundColor(.gray).padding(.top)
                        Button("刷新") { loadItems(reset: true) }
                    }
                    .transition(.opacity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(items) { item in
                                WorkshopGridItem(item: item, isSelected: selectedItem?.id == item.id, isHovering: hoverItemId == item.id)
                                    .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hoverItemId = h ? item.id : nil } }
                                    .onTapGesture { withAnimation(.spring()) { selectedItem = item } }
                            }
                        }
                        .padding()
                        .animation(.easeInOut, value: items)
                        
                        HStack {
                            Button("上一页") { if currentPage > 1 { currentPage -= 1; loadItems(reset: false) } }.disabled(currentPage <= 1)
                            Text("\(currentPage)").monospacedDigit().padding(.horizontal)
                            Button("下一页") { currentPage += 1; loadItems(reset: false) }
                        }.padding(.bottom)
                    }
                    .opacity(isLoading ? 0.3 : 1.0)
                }
                
                if isLoading {
                    ProgressView("加载中...").padding().background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)).cornerRadius(12).shadow(radius: 10).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selectedType) { loadItems(reset: true) }
        .onChange(of: selectedGenre) { loadItems(reset: true) }
        .onChange(of: selectedSort) { loadItems(reset: true) }
        .onAppear {
            if items.isEmpty { loadItems(reset: true) }
        }
    }
    
    private func loadItems(reset: Bool) {
        if reset { currentPage = 1 }
        withAnimation { isLoading = true }
        steam.fetchWorkshopItems(page: currentPage, searchText: searchText, type: selectedType, genre: selectedGenre, sort: selectedSort) { newItems in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation { self.items = newItems; self.isLoading = false }
            }
        }
    }
}

struct WorkshopGridItem: View {
    let item: SteamWorkshopItem
    let isSelected: Bool
    let isHovering: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: item.previewURL) { phase in
                    if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                    else { Color.black.opacity(0.1) }
                }
                .frame(height: 110).clipped()
                
                if isSelected {
                    ZStack {
                        Color.accentColor.opacity(0.6)
                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundColor(.white).shadow(radius: 2)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .frame(height: 34, alignment: .topLeading)
                HStack {
                    Image(systemName: "person.circle.fill").font(.caption2)
                    Text(item.author).font(.caption2).lineLimit(1)
                }.foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3))
        .shadow(color: Color.black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 5 : 2, x: 0, y: 2)
        .scaleEffect(isHovering ? 1.03 : 1.0)
    }
}
