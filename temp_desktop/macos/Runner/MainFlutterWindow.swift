import Cocoa
import FlutterMacOS
import AVFoundation
import VideoToolbox

class MainFlutterWindow: NSWindow {
    
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        
        registerHandlers(controller: flutterViewController);
        
        RegisterGeneratedPlugins(registry: flutterViewController)
        
        super.awakeFromNib()
    }
    
    private func registerHandlers(controller: FlutterViewController) {
        // Event channel for sending texture IDs to Flutter
        let videoStream = FlutterEventChannel(name: "com.openup.media.texture", binaryMessenger: controller.engine.binaryMessenger)
        let streamHandler = VideoStreamHandler()
        videoStream.setStreamHandler(streamHandler)
        
        // Method channel for receiving H.265 packets from Flutter
        let videoControl: FlutterMethodChannel = FlutterMethodChannel(name: "com.openup.media.encoded", binaryMessenger: controller.engine.binaryMessenger)
        videoControl.setMethodCallHandler({ (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard call.method == "decode", let packet = call.arguments as? FlutterStandardTypedData else {
                result(FlutterError(code: "InvalidArgs", message: "Expected Uint8List", details: nil))
                return
            }
            self.handleDecodeMethod(packet: packet, result: result, streamHandler: streamHandler, controller: controller)
        })
    }
    
    private func handleDecodeMethod(packet: FlutterStandardTypedData, result: @escaping FlutterResult, streamHandler: VideoStreamHandler, controller: FlutterViewController) {
        self.performDecode(packet: packet, completion: { pixelBuffer, message in
            if message != nil {
                result(FlutterError(code: "DecoderError", message: message, details: nil))
                return
            }
            guard let pixelBuffer else {
                return
            }
            // Register texture with Flutter
            let texture = FlutterPixelBufferTexture(pixelBuffer: pixelBuffer)
            let textureID = controller.engine.register(texture)

            // Send texture ID back to Flutter
            streamHandler.sendTextureID(NSNumber(value: textureID).intValue)
            result(nil)
        })
    }
    
    private var session: VTDecompressionSession?
    private let attributes: [String: Any] = [
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferOpenGLCompatibilityKey as String: true,
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]
    
    func performDecode(packet: FlutterStandardTypedData, completion: @escaping (CVPixelBuffer?, String?) -> Void) {
        let data = packet.data;
         
         // Create CMSampleBuffer from raw H.265 data
         guard let sampleBuffer = createSampleBuffer(from: data) else {
             completion(nil, "Failed to create sample buffer")
             return
         }
        
         // Ensure VT decompress session is configured
         guard configureDecoderSession(for: sampleBuffer) else {
             completion(nil, "Failed to configure decoder session")
             return
         }
         
         var flagOut = VTDecodeFrameFlags._EnableAsynchronousDecompression
         var flagOut2 = VTDecodeInfoFlags.asynchronous
         var outputPixelBuffer: CVPixelBuffer?
        
        
         let status = VTDecompressionSessionDecodeFrame(
             session!,
             sampleBuffer: sampleBuffer,
             flags: flagOut,
             frameRefcon: nil,
             infoFlagsOut: &flagOut2
//             pixelBuffer: &outputPixelBuffer
         )
         
         guard status == noErr, let decoded = outputPixelBuffer else {
             completion(nil, "Decoding failed with status: \(status)")
             return
         }
         
         completion(decoded, nil)
     }
     
    private func createSampleBuffer(from data: Data) -> CMSampleBuffer? {
        var sampleBuffer: CMSampleBuffer?
        
        // Create a CMBlockBuffer from the Data
        let blockBufferPointer = UnsafeMutablePointer<CMBlockBuffer?>.allocate(capacity: 1)
        
        let status = data.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                return kCVReturnError
            }
            
            // Create a mutable copy of the baseAddress to pass to CMBlockBuffer
            return CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                      memoryBlock: UnsafeMutableRawPointer(mutating: baseAddress), // Mutable pointer
                                                      blockLength: data.count,
                                                      blockAllocator: kCFAllocatorDefault,
                                                      customBlockSource: nil,
                                                      offsetToData: 0,
                                                      dataLength: data.count,
                                                      flags: 0,
                                                      blockBufferOut: blockBufferPointer)
        }
        
        guard status == noErr, let blockBuffer = blockBufferPointer.pointee else {
            return nil
        }
        
        // Create format description for H.265 (HEVC)
//         var formatDescription: CMFormatDescription?
        let (spsData, ppsData) = extractSPSandPPS(from: data)
        guard spsData != nil, ppsData != nil, let validFormatDescription = createHEVCFormatDescription(spsData: spsData!, ppsData: ppsData!) else {
            print("Failed SPSData nil? \(spsData == nil), ppsData \(ppsData == nil)")
            return nil;
            // Use the formatDescription to create a VTDecompressionSession or other tasks
        }
//         let formatStatus = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
//                                                           codecType: kCMVideoCodecType_HEVC,
//                                                           width: 1920, // Use 0 if unknown
//                                                           height: 1080, // Use 0 if unknown
//                                                           extensions: nil,
//                                                           formatDescriptionOut: &formatDescription)
         
//         guard formatStatus == noErr, let validFormatDescription = formatDescription else {
//             return nil
//         }

        // Create a CMSampleBuffer
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: CMTime.invalid, decodeTimeStamp: CMTime.invalid)
        let sampleStatus = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                                dataBuffer: blockBuffer,
                                                dataReady: true,
                                                makeDataReadyCallback: nil,
                                                refcon: nil,
                                                formatDescription: validFormatDescription,
                                                sampleCount: 1,
                                                sampleTimingEntryCount: 1,
                                                sampleTimingArray: &timingInfo,
                                                sampleSizeEntryCount: 1,
                                                sampleSizeArray: [data.count],
                                                sampleBufferOut: &sampleBuffer)

        return sampleStatus == noErr ? sampleBuffer : nil
    }
     
     private func configureDecoderSession(for sampleBuffer: CMSampleBuffer) -> Bool {
         guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
             return false
         }
         
         // Define pixel buffer attributes
         let attributes2: [CFString: Any] = [
             kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelBufferWidthKey: 1920,
             kCVPixelBufferHeightKey: 1080
         ]
         
         var session: VTDecompressionSession?
         let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
             formatDescription: formatDescription,
             decoderSpecification: nil,
             imageBufferAttributes: attributes2 as CFDictionary,
             outputCallback: nil,
             decompressionSessionOut: &session
         )
         
         guard status == noErr else {
             print("Falied to create decompressino session: \(status)")
             return false
         }
         
         self.session = session
         return true
     }
    
    private func createHEVCFormatDescription(spsData: Data, ppsData: Data) -> CMFormatDescription? {
        var formatDescription: CMFormatDescription?

        // Prepare parameter set pointers and sizes
        let parameterSetPointers: [UnsafePointer<UInt8>] = [
            spsData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) },
            ppsData.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) }
        ]
        
        let parameterSetSizes: [Int] = [spsData.count, ppsData.count]
        
        // Call CMVideoFormatDescriptionCreateFromHEVCParameterSets
        let status = parameterSetPointers.withUnsafeBufferPointer { pointers in
            parameterSetSizes.withUnsafeBufferPointer { sizes in
                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: nil, // Use default allocator
                    parameterSetCount: 2,
                    parameterSetPointers: pointers.baseAddress!,
                    parameterSetSizes: sizes.baseAddress!,
                    nalUnitHeaderLength: 4, // Standard NAL unit header length
                    extensions: nil, // No extensions needed for basic use
                    formatDescriptionOut: &formatDescription
                )
            }
        }

        if status == noErr {
            return formatDescription
        } else {
            print("Failed to create format description, status: \(status)")
            return nil
        }
    }
    
    private func extractSPSandPPS(from data: Data) -> (sps: Data?, pps: Data?) {
        var sps: Data?
        var pps: Data?
        
        let startCode = Data([0x00, 0x00, 0x00, 0x01])  // Longer start code
        let alternateStartCode = Data([0x00, 0x00, 0x01])  // Alternate start code
        var index = 0
        
        while index < data.count {
            // Check for start codes
            guard data.count - index > 4 else { break }
            
            let possibleStartCode = data.subdata(in: index..<index+4)
            let isLongStartCode = possibleStartCode == startCode
            let isShortStartCode = possibleStartCode.dropFirst() == alternateStartCode
            
            if isLongStartCode || isShortStartCode {
                let startIndex = isLongStartCode ? index + 4 : index + 3
                guard startIndex < data.count else { break }
                
                let nalUnitType = data[startIndex] & 0x7E >> 1  // Corrected NAL unit type extraction
                
                if nalUnitType == 32 {  // SPS
                    let length = findNALUnitEnd(from: startIndex, in: data) - startIndex
                    sps = data.subdata(in: startIndex..<startIndex + length)
                } else if nalUnitType == 33 {  // PPS
                    let length = findNALUnitEnd(from: startIndex, in: data) - startIndex
                    pps = data.subdata(in: startIndex..<startIndex + length)
                }
                
                // Only increment if we found a valid start code
                index = startIndex
            } else {
                index += 1
            }
        }
        
        return (sps, pps)
    }

    private func findNALUnitEnd(from startIndex: Int, in data: Data) -> Int {
        let startCode = Data([0x00, 0x00, 0x00, 0x01])
        let alternateStartCode = Data([0x00, 0x00, 0x01])
        
        for i in (startIndex + 1)..<data.count {
            // Check for start of next NAL unit
            if i + 3 < data.count {
                let potentialStartCode = data.subdata(in: i..<i+4)
                if potentialStartCode == startCode ||
                   data.subdata(in: i..<i+3) == alternateStartCode {
                    return i
                }
            }
        }
        
        return data.count
    }

//    private func performDecode(packet: FlutterStandardTypedData, completion: @escaping (CVPixelBuffer?, String?) -> Void) {
//        // Decode H.265 here
//        let h265Data = packet.data
//        var formatDesc: CMFormatDescription?
//        var session: VTDecompressionSession?
//        var pixelBuffer: CVPixelBuffer?
//        
//        print("H.265 Data Length: \(h265Data.count)")
//        h265Data.withUnsafeBytes { rawBufferPointer in
//            let bytes = Array(rawBufferPointer.bindMemory(to: UInt8.self))
//            print("First 10 bytes: \(bytes.prefix(10))")
//        }
//
//        let callback: VTDecompressionOutputCallback = {
//                (refcon: UnsafeMutableRawPointer?,
//                 sourceFrameRefcon: UnsafeMutableRawPointer?,
//                 status: OSStatus,
//                 infoFlags: VTDecodeInfoFlags,
//                 imageBuffer: CVImageBuffer?,
//                 presentationTimeStamp: CMTime,
//                 presentationDuration: CMTime) -> Void in
//                
//                if status == noErr, let imageBuffer = imageBuffer {
//                    guard let pixelBufferPtr = refcon?.assumingMemoryBound(to: CVPixelBuffer?.self) else {
//                        return
//                    }
//                    pixelBufferPtr.pointee = imageBuffer as? CVPixelBuffer
//                    completion(pixelBufferPtr.pointee, nil);
//                }
//            }
//
//        let params: [NSString: Any] = [:]
//        let attrs: [NSString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
//
//        // Initialize CMFormatDescription for H.265
//        let statusDesc = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
//            allocator: nil,
//            parameterSetCount: 1,
//            parameterSetPointers: [UnsafePointer<UInt8>(h265Data.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self) })],
//            parameterSetSizes: [h265Data.count],
//            nalUnitHeaderLength: 4,
//            extensions: nil,
//            formatDescriptionOut: &formatDesc
//        )
//        
//        guard statusDesc == noErr, let formatDesc = formatDesc else {
//            completion(nil, "DecoderError: Failed to create format description")
//            return
//        }
//
//        // Initialize VTDecompressionSession
//        let statusSession = VTDecompressionSessionCreate(
//            allocator: nil,
//            formatDescription: formatDesc,
//            decoderSpecification: nil,
//            imageBufferAttributes: attrs as CFDictionary?,
//            decompressionSessionOut: &session
//        )
//
//        guard statusSession == noErr, let session = session else {
//            completion(nil, "DecoderError: Failed to create decompression session")
//            return
//        }
//
//        // Decode the frame
//        var blockBuffer: CMBlockBuffer?
//        h265Data.withUnsafeBytes { rawBufferPointer in
//            CMBlockBufferCreateWithMemoryBlock(
//                allocator: kCFAllocatorDefault,
//                memoryBlock: UnsafeMutableRawPointer(mutating: rawBufferPointer.baseAddress),
//                blockLength: h265Data.count,
//                blockAllocator: kCFAllocatorNull,
//                customBlockSource: nil,
//                offsetToData: 0,
//                dataLength: h265Data.count,
//                flags: 0,
//                blockBufferOut: &blockBuffer
//            )
//        }
//
//        guard let blockBuffer = blockBuffer else {
//            completion(nil, "BlockBufferError: Failed to create block buffer")
//            return
//        }
//        
//        let decodeFlags: VTDecodeFrameFlags = []
//        let decodeStatus = VTDecompressionSessionDecodeFrame(
//            session,
//            sampleBuffer: blockBuffer as! CMSampleBuffer,
//            flags: decodeFlags,
//            frameRefcon: nil,
//            infoFlagsOut: nil
//        )
//
//        guard decodeStatus == noErr, let pixelBuffer = pixelBuffer else {
//            completion(nil, "DecodeError: Failed to decode frame")
//            return
//        }
//    }
}


class VideoStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  func sendTextureID(_ textureID: Int) {
    eventSink?(textureID)
  }
}

class FlutterPixelBufferTexture: NSObject, FlutterTexture {
    private var pixelBuffer: CVPixelBuffer
    
    init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
        super.init()
    }
    

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        return Unmanaged.passRetained(pixelBuffer)
    }
}
