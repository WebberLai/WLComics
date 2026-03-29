//
//  StringUtility.swift
//  Pods
//
//  Created by ray.lee on 2017/6/12.
//  Updated: 2026/03 - 修復 deprecated API 和 force unwrap
//

import Foundation

open class StringUtility{
    public static let ENCODE_BIG5 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue))
    public static let ENCODE_GB2312 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))

    public init() {
    }

    open class func count(_ source : String) -> Int{
        return source.count
    }

    open class func indexOf(source : String, search : String) -> Range<String.Index>?{
        return source.range(of: search)
    }

    open class func lastIndexOf(source : String, target: String) -> Int {
        guard let ret = source.range(of: target, options: .backwards) else {
            return -1
        }
        return source.distance(from: source.startIndex, to: ret.lowerBound)
    }

    open class func indexOfInt(_ source : String, _ search : String) -> Int{
        guard let range = source.range(of: search) else { return -1 }
        return source.distance(from: source.startIndex, to: range.lowerBound)
    }

    open class func indexOfUpper(source : String, search : String) -> String.Index?{
        return source.range(of: search)?.upperBound
    }

    open class func indexOfLower(source : String, search : String) -> String.Index?{
        return source.range(of: search)?.lowerBound
    }

    open class func substring(source : String, upper : String.Index, lower : String.Index) -> String{
        guard upper <= lower, upper >= source.startIndex, lower <= source.endIndex else {
            return ""
        }
        return String(source[upper..<lower])
    }

    open class func substring(_ source : String,_ upperString : String,_ lowerString : String ) -> String?{
        guard let upper = indexOfUpper(source: source, search: upperString),
              let lower = indexOfLower(source: source, search: lowerString),
              upper <= lower else {
            return nil
        }
        return String(source[upper..<lower])
    }

    open class func lastSubstring(_ source : String,_ upperString : String,_ lowerString : String ) -> String?{
        let upperIndex = lastIndexOf(source: source, target: upperString)
        let lowerIndex = lastIndexOf(source: source, target: lowerString)

        guard upperIndex != -1, lowerIndex != -1 else { return nil }
        let startPos = upperIndex + upperString.count
        guard startPos <= lowerIndex, startPos <= source.count, lowerIndex <= source.count else { return nil }
        return substring(source, startPos, lowerIndex)
    }

    open class func substring(source : String, beginIndex : String.Index) -> String{
        guard beginIndex >= source.startIndex, beginIndex <= source.endIndex else { return "" }
        return String(source[beginIndex...])
    }

    //like JAVA String.substring(beginIndex, endIndex)
    open class func substring(_ source : String, _ beginIndex : Int, _ endIndex : Int ) -> String{
        guard beginIndex >= 0, endIndex >= beginIndex, endIndex <= source.count else {
            return ""
        }
        let beginInx = source.index(source.startIndex, offsetBy: beginIndex)
        let endInx = source.index(source.startIndex, offsetBy: endIndex)
        return String(source[beginInx..<endInx])
    }

    open class func dataToStringBig5(data : Data) -> String{
        // 先嘗試 UTF-8（新網站已改用 UTF-8），再嘗試 Big5
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = NSString(data: data, encoding: ENCODE_BIG5) {
            return string as String
        }
        return ""
    }

    open class func dataToStringGB2312(data : Data) -> String{
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = NSString(data: data, encoding: ENCODE_GB2312) {
            return string as String
        }
        return ""
    }

    open class func split(_ source : String, separatedBy : String) -> [String]{
        return source.components(separatedBy: separatedBy)
    }

    open class func trim(_ source : String) -> String{
        return source.trimmingCharacters(in: .whitespaces)
    }

    open class func replace(_ source : String, _ of : String,_ with : String) -> String{
        return source.replacingOccurrences(of: of, with: with)
    }

    open class func urlEncodeUsingBIG5(_ source : String) -> String{
        return urlEncode(source, ENCODE_BIG5)
    }

    open class func urlEncodeUsingGB2312(_ source : String) -> String{
        return urlEncode(source, ENCODE_GB2312)
    }

    open class func urlEncode(_ source : String,_ encode: UInt) -> String{
        guard let encodeUrlString = source.data(using: String.Encoding(rawValue: encode), allowLossyConversion: true) else {
            return ""
        }
        return encodeUrlString.hexEncodedString()
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%%%02hhX", $0) }.joined()
    }
}
