//
//  catMediaApp.swift
//  catMedia
//
//  Created by Rushabh Variya on 15/04/26.
//

import SwiftUI

@main
struct MediaConverterApp: App {
    init() {
        do {
            _ = try FileService().ensureAppOutputDirectoryExists()
        } catch {
            print("[catMedia][FileService] Failed to create app output folder: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
