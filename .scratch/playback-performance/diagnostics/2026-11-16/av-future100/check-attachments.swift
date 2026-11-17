import Foundation
import CoreVideo
import CoreMedia
var p:CVPixelBuffer?;CVPixelBufferCreate(nil,16,16,kCVPixelFormatType_32BGRA,nil,&p)
var f:CMVideoFormatDescription?;CMVideoFormatDescriptionCreateForImageBuffer(allocator:nil,imageBuffer:p!,formatDescriptionOut:&f)
var t=CMSampleTimingInfo(duration:CMTime(value:1,timescale:60),presentationTimeStamp:CMTime(seconds:100,preferredTimescale:1000000),decodeTimeStamp:.invalid);var b:CMSampleBuffer?
CMSampleBufferCreateReadyWithImageBuffer(allocator:nil,imageBuffer:p!,formatDescription:f!,sampleTiming:&t,sampleBufferOut:&b)
let arr=CMSampleBufferGetSampleAttachmentsArray(b!,createIfNecessary:true)! as NSArray
let dict=arr[0] as! NSMutableDictionary
dict[kCMSampleAttachmentKey_DisplayImmediately]=true
print("after true",CMSampleBufferGetSampleAttachmentsArray(b!,createIfNecessary:false)!)
dict[kCMSampleAttachmentKey_DisplayImmediately]=false
print("after false",CMSampleBufferGetSampleAttachmentsArray(b!,createIfNecessary:false)!)
print("PTS",CMTimeGetSeconds(CMSampleBufferGetOutputPresentationTimeStamp(b!)))
