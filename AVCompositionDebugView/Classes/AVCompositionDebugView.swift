
import UIKit
import AVFoundation

fileprivate let kLeftInsetToMatchTimeSlider: CGFloat = 50
fileprivate let kRightInsetToMatchTimeSlider: CGFloat = 60
fileprivate let kLeftMarginInset: CGFloat = 4
fileprivate let kBannerHeight: CGFloat = 20
fileprivate let kIdealRowHeight: CGFloat = 36
fileprivate let kGapAfterRows: CGFloat = 4

extension NSString {
    func drawVerticallyCentered(
        in rect: CGRect,
        withAttributes attributes: [NSAttributedStringKey: Any]?) {

        var newRect = rect

        let size = self.size(withAttributes: attributes)
        newRect.origin.y += (rect.size.height - size.height)
        self.draw(in: newRect, withAttributes: attributes)
    }
}

struct APLCompositionTrackSegmentInfo {
    var timeRange = CMTimeRange()
    var empty: Bool = true
    var mediaType: AVMediaType? = nil
    var description: String = ""
}

struct APLVideoCompositionStageInfo {
    var timeRange = CMTimeRange()
    var layerNames: [String] = []
    var opacityRamps: [String: [CGPoint]] = [:]
}

class AVCompositionDebugView: UIView {

    private var drawingLayer: CALayer {
        return self.layer
    }

    var player: AVPlayer!

    private var duration = CMTime(value: 1, timescale: 1) // Avoid division by zero later
    private var compositionRectWidth: CGFloat = 0

    private var compositionTracks: [[APLCompositionTrackSegmentInfo]]?
    private var audioMixTracks: [[CGPoint]]?
    private var videoCompositionStages: [APLVideoCompositionStageInfo]?

    private var scaledDurationToWidth: CGFloat = 0

    func synchronize(to composition: AVComposition,
                     videoComposition: AVVideoComposition,
                     audioMix: AVAudioMix) {

        compositionTracks = nil
        audioMixTracks = nil
        videoCompositionStages = nil

        duration = CMTimeMake(1, 1) // avoid division by zero later

        compositionTracks = extractFromComposition(composition)
        duration = CMTimeMaximum(duration, composition.duration);

        audioMixTracks = extractFromAudioMix(audioMix)

        videoCompositionStages = extractFromVideoComposition(videoComposition)

        drawingLayer.setNeedsDisplay()
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)

        drawingLayer.frame = self.bounds
        drawingLayer.setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {

        let context = UIGraphicsGetCurrentContext()

        let rect = rect.insetBy(dx: kLeftMarginInset, dy: 4.0)

        let style = NSMutableParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle

        style.alignment = .center

        let textAttributes: [NSAttributedStringKey: Any] = [
            .foregroundColor: UIColor.white,
            .paragraphStyle: style,
        ]


        let numBanners = (compositionTracks != nil ? 1 : 0) +
            (audioMixTracks != nil ? 1 : 0) +
            (videoCompositionStages != nil ? 1 : 0)

        let numRows = (compositionTracks?.count ?? 0)
            + (audioMixTracks?.count ?? 0)
            + (videoCompositionStages != nil ? 1 : 0)

        let totalBannerHeight = CGFloat(numBanners) * (kBannerHeight * kGapAfterRows)
        var rowHeight = kIdealRowHeight

        if numRows > 0 {
            let maxRowHeight = (rect.size.height - totalBannerHeight) / CGFloat(numRows)
            rowHeight = min(rowHeight, maxRowHeight)
        }

        var runningTop = rect.origin.y
        var bannerRect = rect

        bannerRect.size.height = kBannerHeight
        bannerRect.origin.y = runningTop

        var rowRect = rect
        rowRect.size.height = rowHeight

        rowRect.origin.x += kLeftInsetToMatchTimeSlider
        rowRect.size.width -= (kLeftInsetToMatchTimeSlider + kRightInsetToMatchTimeSlider)
        self.compositionRectWidth = rowRect.size.width

        self.scaledDurationToWidth = compositionRectWidth / CGFloat(duration.seconds)

        if let compositionTracks = compositionTracks {
            bannerRect.origin.y = runningTop
            context?.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)

            NSString(string: "AVComposition").draw(
                in: bannerRect,
                withAttributes: [ .foregroundColor: UIColor.white ])

            runningTop += bannerRect.size.height

            compositionTracks.forEach { track in
                rowRect.origin.y = runningTop
                var segmentRect = rowRect

                track.forEach { segment in

                    segmentRect.size.width = CGFloat(segment.timeRange.duration.seconds) * scaledDurationToWidth

                    if segment.empty {
                        context?.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
                        NSString(string: "Empty").drawVerticallyCentered(
                            in: segmentRect,
                            withAttributes: textAttributes)
                    } else {
                        if segment.mediaType == .video {
                            context?.setFillColor(red: 0, green: 0.36, blue: 0.36, alpha: 1) // blue-green
                            context?.setStrokeColor(red: 0, green: 0.5, blue: 0.5, alpha: 1) // lighter blue-green
                        } else {
                            context?.setFillColor(red: 0, green: 0.24, blue: 0.36, alpha: 1) // bluer-green
                            context?.setStrokeColor(red: 0, green: 0.33, blue: 0.6, alpha: 1) // lighter bluer-green
                        }
                        context?.setLineWidth(2)
                        context?.addRect(segmentRect.insetBy(dx: 3, dy: 3))
                        context?.drawPath(using: .fillStroke)

                        context?.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
                        NSString(string: segment.description).drawVerticallyCentered(
                            in: segmentRect,
                            withAttributes: textAttributes)
                    }

                    segmentRect.origin.x += segmentRect.size.width
                }

                runningTop += rowRect.size.height
            }

            runningTop += kGapAfterRows
        }

        if let videoCompositionStages = videoCompositionStages {

            bannerRect.origin.y = runningTop
            context?.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)

            NSString(string: "AVVideoComposition").draw(
                in: bannerRect,
                withAttributes: [ .foregroundColor: UIColor.white ])

            runningTop += bannerRect.size.height

            rowRect.origin.y = runningTop
            var stageRect = rowRect

            videoCompositionStages.forEach { (stage: APLVideoCompositionStageInfo) in

                stageRect.size.width = CGFloat(stage.timeRange.duration.seconds) * scaledDurationToWidth

                let layerCount = stage.layerNames.count
                var layerRect = stageRect

                if layerCount > 0 {
                    layerRect.size.height /= CGFloat(layerCount)
                }

                stage.layerNames.forEach { layerName in

                    if Int(layerName) ?? 0 % 2 == 1 {
                        context?.setFillColor(red: 0.55, green: 0.02, blue: 0.02, alpha: 1) // darker red
                        context?.setStrokeColor(red: 0.87, green: 0.1, blue: 0.1, alpha: 1) // brighter red
                    } else {
                        context?.setFillColor(red: 0, green: 0.4, blue: 0.76, alpha: 1) // darker blue
                        context?.setStrokeColor(red: 0, green: 0.67, blue: 1, alpha: 1) // brighter blue
                    }

                    context?.setLineWidth(2)
                    context?.addRect(layerRect.insetBy(dx: 3, dy: 1))
                    context?.drawPath(using: .fillStroke)

                    // (if there are two layers, the first should ideally have a gradient fill.)

                    context?.setFillColor(red: 1, green: 1, blue: 1, alpha: 1) // white

                    NSString(string: layerName).drawVerticallyCentered(
                        in: layerRect,
                        withAttributes: textAttributes)

                    let rampArray = stage.opacityRamps[layerName] ?? []

                    if !rampArray.isEmpty {
                        var rampRect = layerRect

                        rampRect.size.width = CGFloat(duration.seconds) * scaledDurationToWidth
                        rampRect = rampRect.insetBy(dx: 3, dy: 3)

                        context?.beginPath()
                        context?.setStrokeColor(red: 0.95, green: 0.68, blue: 0.09, alpha: 1) // yellow
                        context?.setLineWidth(2)
                        var firstPoint = true

                        rampArray.forEach { timeVolumePoint in

                            var pointInRow = CGPoint(
                                x: self.horizontalPosition(for: CMTime(seconds: Double(timeVolumePoint.x), preferredTimescale: 1)) - 3,
                                y: rampRect.origin.y + (0.9 - 0.8 * timeVolumePoint.y))

                            pointInRow.x = max(pointInRow.x, rampRect.minX)
                            pointInRow.x = min(pointInRow.x, rampRect.maxX)

                            if firstPoint {
                                context?.move(to: pointInRow)
                                firstPoint = false
                            } else {
                                context?.addLine(to: pointInRow)
                            }
                        }

                        context?.strokePath()
                    }

                    layerRect.origin.y += layerRect.size.height
                }

                stageRect.origin.x += stageRect.size.width
            }

            runningTop += rowRect.size.height
            runningTop += kGapAfterRows
        }

        if let audioMixTracks = audioMixTracks {

            bannerRect.origin.y = runningTop
            context?.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)

            NSString(string: "AVAudioMix").draw(
                in: bannerRect,
                withAttributes: [ .foregroundColor: UIColor.white ])

            runningTop += bannerRect.size.height

            for mixTrack in audioMixTracks {
                rowRect.origin.y = runningTop

                var rampRect = rowRect
                rampRect.size.width = CGFloat(duration.seconds) * scaledDurationToWidth
                rampRect = rampRect.insetBy(dx: 3, dy: 3)

                context?.setFillColor(red: 0.55, green: 0.02, blue: 0.02, alpha: 1)
                context?.setStrokeColor(red: 0.87, green: 0.10, blue: 0.10, alpha: 1)

                context?.setLineWidth(2)
                context?.addRect(rampRect)
                context?.drawPath(using: .fillStroke)

                context?.beginPath()
                context?.setStrokeColor(red: 0.95, green: 0.68, blue: 0.09, alpha: 1)
                context?.setLineWidth(2)

                var firstPoint = true

                mixTrack.forEach { timeVolumePoint in

                    var pointRow = CGPoint(
                        x: rampRect.origin.x + timeVolumePoint.x * scaledDurationToWidth,
                        y: rampRect.origin.y + (0.9 - 0.8 * timeVolumePoint.x) * scaledDurationToWidth)

                    pointRow.x = max(pointRow.x, rampRect.minX)
                    pointRow.x = min(pointRow.x, rampRect.maxX)

                    if firstPoint {
                        context?.move(to: pointRow)
                        firstPoint = false
                    } else {
                        context?.addLine(to: pointRow)
                    }
                }

                context?.strokePath()

                runningTop += rowRect.size.height
            }

            runningTop += kGapAfterRows
        }

        if let currentItem = player?.currentItem {

            self.layer.sublayers = nil
            let visibleRect = self.layer.bounds
            var currentTimeRect = visibleRect

            currentTimeRect.origin.x = 0
            currentTimeRect.size.width = 0

            let timeMarkerRedBandLayer = CAShapeLayer()
            timeMarkerRedBandLayer.frame = currentTimeRect
            timeMarkerRedBandLayer.position = CGPoint(
                x: rowRect.origin.x,
                y: self.bounds.size.height / 2)

            let linePath = CGPath(rect: currentTimeRect, transform: nil)

            timeMarkerRedBandLayer.fillColor = UIColor.red.withAlphaComponent(0.5).cgColor
            timeMarkerRedBandLayer.path = linePath

            currentTimeRect.origin.x = 0
            currentTimeRect.size.width = 1

            let timeMarkerWhiteLineLayer = CAShapeLayer()
            timeMarkerWhiteLineLayer.frame = currentTimeRect
            timeMarkerWhiteLineLayer.position = CGPoint(x: 4, y: bounds.size.height / 2)
            let whiteLinePath = CGPath(rect: currentTimeRect, transform: nil)
            timeMarkerWhiteLineLayer.fillColor = UIColor.white.cgColor
            timeMarkerWhiteLineLayer.path = whiteLinePath

            // Add the white line layer to red band layer, by doing so we can only animate the red band layer which in turn animates its sublayers
            timeMarkerRedBandLayer.addSublayer(timeMarkerWhiteLineLayer)

            let scrubbingAnimation = CABasicAnimation(keyPath: "position.x")
            scrubbingAnimation.fromValue = NSNumber(value: Float(horizontalPosition(for: kCMTimeZero)))
            scrubbingAnimation.toValue = NSNumber(value: Float(horizontalPosition(for: duration)))
            scrubbingAnimation.isRemovedOnCompletion = false
            scrubbingAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            scrubbingAnimation.duration = duration.seconds
            scrubbingAnimation.fillMode = kCAFillModeBoth
            timeMarkerRedBandLayer.add(scrubbingAnimation, forKey: nil)

            let syncLayer = AVSynchronizedLayer(playerItem: currentItem)
            syncLayer.addSublayer(timeMarkerRedBandLayer)

            self.layer.addSublayer(syncLayer)
        }
    }

    func horizontalPosition(for time: CMTime) -> CGFloat {
        var seconds: CGFloat = 0

        if CMTIME_IS_NUMERIC(time), time > kCMTimeZero {
            seconds = CGFloat(time.seconds)
        }

        return seconds * scaledDurationToWidth + kLeftInsetToMatchTimeSlider + kLeftMarginInset
    }
}

// MARK: - Data extraction utilities
extension AVCompositionDebugView {

    private func extractFromVideoComposition(_ videoComposition: AVVideoComposition) -> [APLVideoCompositionStageInfo] {

        return videoComposition.instructions.compactMap {
            (instruction: AVVideoCompositionInstructionProtocol) -> APLVideoCompositionStageInfo? in

            var stage = APLVideoCompositionStageInfo()

            stage.timeRange = instruction.timeRange

            var rampDictionary: [String: [CGPoint]] = [:]

            guard let instruction = instruction as? AVVideoCompositionInstruction else { return nil }

            let layerNames = instruction.layerInstructions.map {
                (layerInstruction: AVVideoCompositionLayerInstruction) -> String in

                var ramp: [CGPoint] = []
                var startTime: CMTime = kCMTimeZero

                var startOpacity: Float = 1
                var endOpacity: Float = 1
                var timeRange = CMTimeRange()

                while !layerInstruction.getOpacityRamp(
                    for: startTime,
                    startOpacity: &startOpacity,
                    endOpacity: &endOpacity,
                    timeRange: &timeRange) {

                        if startTime == kCMTimeZero, timeRange.start > kCMTimeZero {
                            ramp.append(CGPoint(x: timeRange.start.seconds, y: Double(startOpacity)))
                        }

                        ramp.append(CGPoint(x: timeRange.end.seconds, y: Double(endOpacity)))
                        startTime = timeRange.end
                }

                let name = String(format: "%d", layerInstruction.trackID)
                rampDictionary[name] = ramp
                return name
            }

            if layerNames.count > 1 {
                stage.opacityRamps = rampDictionary
            }

            stage.layerNames = layerNames
            return stage
        }
    }

    private func extractFromAudioMix(_ audioMix: AVAudioMix) -> [[CGPoint]] {
        return audioMix.inputParameters.map {
            (input: AVAudioMixInputParameters) -> [CGPoint] in

            var ramp: [CGPoint] = []

            var startTime: CMTime = kCMTimeZero
            var startVolume: Float = 1.0
            var endVolume: Float = 1.0

            var timeRange = CMTimeRange()

            while input.getVolumeRamp(for: startTime, startVolume: &startVolume, endVolume: &endVolume, timeRange: &timeRange) {

                if startTime == kCMTimeZero, timeRange.start > kCMTimeZero {
                    ramp.append(CGPoint(x: 0, y: 1))
                    ramp.append(CGPoint(x: timeRange.start.seconds, y: 1))
                }

                ramp.append(CGPoint(x: timeRange.start.seconds, y: Double(startVolume)))
                ramp.append(CGPoint(x: timeRange.end.seconds, y: Double(endVolume)))

                startTime = timeRange.end
            }

            if startTime < duration {
                ramp.append(CGPoint.init(x: duration.seconds, y: Double(endVolume)))
            }

            return ramp
        }
    }

    private func extractFromComposition(_ composition: AVComposition) -> [[APLCompositionTrackSegmentInfo]] {
        return composition.tracks.map { t in

            return t.segments.map { (s: AVCompositionTrackSegment) -> APLCompositionTrackSegmentInfo in

                var segment = APLCompositionTrackSegmentInfo()

                if s.isEmpty {
                    segment.timeRange = s.timeMapping.target // only used for duration
                } else {
                    segment.timeRange = s.timeMapping.source // assumes non-scaled edit
                    segment.empty = s.isEmpty
                    segment.mediaType = t.mediaType
                }

                if !s.isEmpty {
                    var description = String(
                        format: "%1.1f - %1.1f: \"%@\" ",
                        segment.timeRange.start.seconds,
                        segment.timeRange.end.seconds,
                        s.sourceURL?.lastPathComponent ?? "nil")

                    if let type = segment.mediaType {
                        switch type {
                        case .video: description.append("(v)")
                        case .audio: description.append("(a)")
                        default: description.append("(\(type.rawValue))")
                        }
                    }

                    segment.description = description
                }

                return segment
            }
        }
    }
}

