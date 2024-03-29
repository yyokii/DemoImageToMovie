//
//  Service.swift
//  DemoImageToMovie
//
//  Created by Higashihara Yoki on 2023/08/22.
//

import AVFoundation
import UIKit
import Photos

struct RenderSettings {

    var size : CGSize = .zero
    var fps: Int32 = 6   // frames per second
    var avCodecKey = AVVideoCodecType.h264
    var videoFilename = "render"
    var videoFilenameExt = "mp4"

    var outputURL: URL {
        // Use the CachesDirectory so the rendered video file sticks around as long as we need it to.
        // Using the CachesDirectory ensures the file won't be included in a backup of the app.
        let fileManager = FileManager.default
        if let tmpDirURL = try? fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            return tmpDirURL.appendingPathComponent(videoFilename).appendingPathExtension(videoFilenameExt)
        }
        fatalError("URLForDirectory() failed")
    }
}

/**
 画像から動画を生成する
 */
class ImageAnimator {

    // Apple suggests a timescale of 600 because it's a multiple of standard video rates 24, 25, 30, 60 fps etc.
    static let kTimescale: Int32 = 600

    let settings: RenderSettings
    let videoWriter: VideoWriter
    var images: [UIImage]!

    var frameNum = 0

    class func removeFileAtURL(fileURL: URL) {
        do {
            try FileManager.default.removeItem(atPath: fileURL.path)
        }
        catch _ as NSError {
            // Assume file doesn't exist.
        }
    }

    init(renderSettings: RenderSettings) {
        settings = renderSettings
        videoWriter = VideoWriter(renderSettings: settings)
        //images = loadImages()
    }

    func render(completion: (()->Void)?) {

        // The VideoWriter will fail if a file exists at the URL, so clear it out first.
        ImageAnimator.removeFileAtURL(fileURL: settings.outputURL)

        videoWriter.prepareToWriteVideo()
        videoWriter.startWritingVideo(appendPixelBuffers: appendPixelBuffers) {
            completion?()
        }
    }

    func appendPixelBuffers(writer: VideoWriter) -> Bool {

        let frameDuration = CMTimeMake(
            value: Int64(ImageAnimator.kTimescale / settings.fps),
            timescale: ImageAnimator.kTimescale
        )

        while !images.isEmpty {
            if writer.isReadyForData == false {
                // Inform writer we have more buffers to write.
                return false
            }

            let image = images.removeFirst()
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameNum))
            let success = videoWriter.addFrameFromImage(image: image, withPresentationTime: presentationTime)
            if success == false {
                fatalError("addImage() failed")
            }

            frameNum += 1
        }

        // Inform writer all buffers have been written.
        return true
    }
}

/**
 動画作成処理を担う

 AVAssetWriterの生成
 → （AVAssetWriterInputPixelBufferAdaptorを介して）AVAssetWriterInputを利用してメディアデータを入力
 という一連の処理を担う
 */
class VideoWriter {

    let renderSettings: RenderSettings

    var videoWriter: AVAssetWriter!
    var videoWriterInput: AVAssetWriterInput!
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!

    var isReadyForData: Bool {
        return videoWriterInput?.isReadyForMoreMediaData ?? false
    }

    init(renderSettings: RenderSettings) {
        self.renderSettings = renderSettings
    }

    /// UIImageをCVPixelBufferに変換する
    class func pixelBufferFromImage(image: UIImage, pixelBufferPool: CVPixelBufferPool, size: CGSize) -> CVPixelBuffer {

        var pixelBufferOut: CVPixelBuffer?

        // pixel bufferの作成
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)
        if status != kCVReturnSuccess {
            fatalError("CVPixelBufferPoolCreatePixelBuffer() failed")
        }

        let pixelBuffer = pixelBufferOut!

        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        let data = CVPixelBufferGetBaseAddress(pixelBuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        // UIImageを描画するために利用するグラフィックコンテキスト
        let context = CGContext(
            data: data,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )

        context!.clear(CGRect(x:0,y: 0,width: size.width,height: size.height))

        // UIImageのアスペクト比を維持しながら、指定されたサイズに合わせて中央に描画するように値を計算
        let horizontalRatio = size.width / image.size.width
        let verticalRatio = size.height / image.size.height
        // aspectRatio = max(horizontalRatio, verticalRatio) // ScaleAspectFill
        let aspectRatio = min(horizontalRatio, verticalRatio) // ScaleAspectFit

        let newSize = CGSize(width: image.size.width * aspectRatio, height: image.size.height * aspectRatio)
        // 描画の起点は左上なので、中央描画のためにオフセットが必要かどうかを計算
        let x = newSize.width < size.width ? (size.width - newSize.width) / 2 : 0
        let y = newSize.height < size.height ? (size.height - newSize.height) / 2 : 0

        context?.draw(image.cgImage!, in: CGRect(x:x, y: y, width: newSize.width, height: newSize.height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        return pixelBuffer
    }

    /**
     動画の書き込みを開始するためのセットアップを行う。
     具体的には、動画の出力設定、AVAssetWriterの初期化、セッションの開始などが行われる。
     */
    func prepareToWriteVideo() {
        let avOutputSettings: [String: Any] = [
            AVVideoCodecKey: renderSettings.avCodecKey,
            AVVideoWidthKey: NSNumber(value: Float(renderSettings.size.width)),
            AVVideoHeightKey: NSNumber(value: Float(renderSettings.size.height))
        ]

        func createAssetWriter(outputURL: URL) -> AVAssetWriter {
            guard let assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4) else {
                fatalError("AVAssetWriter() failed")
            }

            guard assetWriter.canApply(outputSettings: avOutputSettings, forMediaType: AVMediaType.video) else {
                fatalError("canApplyOutputSettings() failed")
            }

            return assetWriter
        }

        videoWriter = createAssetWriter(outputURL: renderSettings.outputURL)
        videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: avOutputSettings)

        if videoWriter.canAdd(videoWriterInput) {
            videoWriter.add(videoWriterInput)
        }
        else {
            fatalError("canAddInput() returned false")
        }

        // The pixel buffer adaptor must be created before we start writing.
        let sourcePixelBufferAttributesDictionary = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: NSNumber(value: Float(renderSettings.size.width)),
            kCVPixelBufferHeightKey as String: NSNumber(value: Float(renderSettings.size.height))
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary
        )

        if videoWriter.startWriting() == false {
            fatalError("startWriting() failed")
        }

        videoWriter.startSession(atSourceTime: CMTime.zero)

        precondition(pixelBufferAdaptor.pixelBufferPool != nil, "nil pixelBufferPool")
    }

    /**
     ピクセルバッファ（画像データ）を動画に追加する処理を非同期で実行する。
     */
    func startWritingVideo(appendPixelBuffers: ((VideoWriter)->Bool)?, completion: (()->Void)?) {

        precondition(videoWriter != nil, "Call start() to initialze the writer")

        let queue = DispatchQueue(label: "mediaInputQueue")
        videoWriterInput.requestMediaDataWhenReady(on: queue) {
            let isFinished = appendPixelBuffers?(self) ?? false
            if isFinished {
                self.videoWriterInput.markAsFinished()
                self.videoWriter.finishWriting() {
                    DispatchQueue.main.async {
                        completion?()
                    }
                }
            }
            else {
                // Fall through. The closure will be called again when the writer is ready.
            }
        }
    }

    func addFrameFromImage(image: UIImage, withPresentationTime presentationTime: CMTime) -> Bool {

        precondition(pixelBufferAdaptor != nil, "Call start() to initialze the writer")

        let pixelBuffer = VideoWriter.pixelBufferFromImage(
            image: image,
            pixelBufferPool: pixelBufferAdaptor.pixelBufferPool!,
            size: renderSettings.size
        )
        return pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }
}
