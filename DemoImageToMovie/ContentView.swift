//
//  ContentView.swift
//  DemoImageToMovie
//
//  Created by Higashihara Yoki on 2023/08/22.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @State private var movieURL: URL?

    var body: some View {
        VStack {
            Button {
                crateMovie()
            } label: {
                Text("image to movie")
            }

            if let movieURL {
                VideoPlayer(player: .init(url: movieURL))
                    .frame(width: 400)
            }
        }
        .padding()
    }

    func crateMovie() {
        let settings = RenderSettings(size: .init(width: 400, height: 400))
        let imageAnimator = ImageAnimator(renderSettings: settings)
        let images: [UIImage] = [
            UIImage(named: "demo1")!,
            UIImage(named: "demo2")!,
            UIImage(named: "demo3")!,
            UIImage(named: "demo4")!
        ]
        imageAnimator.images = images
        imageAnimator.render() {
            print("finish")
            movieURL = settings.outputURL
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
