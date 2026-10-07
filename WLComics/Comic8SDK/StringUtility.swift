//
//  File.swift
//  Comic8SDK
//
//  Created by ray.lee on 2017/6/12.
//
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
    
    open class func lastIndexOf( source : String, target: String) -> Int {
        let ret = source.range(of: target, options: .backwards)
        
        if( ret != nil){
            let result = source.distance(from: source.startIndex, to: (ret?.lowerBound)!)
            
            return result
        }
        
        return -1
    }
    
    open class func indexOfInt(_ source : String, _ search : String) -> Int{
        let range = source.range(of: search)
        let result = source.distance(from: source.startIndex, to: (range?.lowerBound)!)
        
        return result;
    }
    
    open class func indexOfUpper(source : String, search : String) -> String.Index?{
        let range =  source.range(of: search)
        
        guard range != nil else {
            return nil
        }
        
        return range?.upperBound;
    }
    
    open class func indexOfLower(source : String, search : String) -> String.Index?{
        let range =  source.range(of: search)
        
        guard range != nil else {
            return nil
        }
        
        return range?.lowerBound;
    }
    
    open class func substring(source : String, upper : String.Index, lower : String.Index) -> String{
        let range = upper ..< lower
        
        return String(source[range])
    }
    
    open class func substring(_ source : String,_ upperString : String,_ lowerString : String ) -> String?{
        let upper : String.Index? = indexOfUpper(source: source, search: upperString)
        let lower : String.Index? = indexOfLower(source: source, search: lowerString)
        
        if(upper != nil && lower != nil){
            let range = upper! ..< lower!
            
            return String(source[range])
        }
        
        return nil
    }
    
    open class func lastSubstring(_ source : String,_ upperString : String,_ lowerString : String ) -> String?{
        
        let upperIndex = lastIndexOf(source: source, target: upperString)
        let lowerIndex = lastIndexOf(source: source, target: lowerString)
        
        if(upperIndex != -1 && lowerIndex != -1){
            return substring(source, upperIndex + upperString.count, lowerIndex)
        }
        
        return nil
    }
    
    open class func substring(source : String, beginIndex : String.Index) -> String{
        return String(source[beginIndex...])
            //source.substring(from: beginIndex)
    }
    
    //like JAVA String.substring(beginIndex, endIndex)
    open class func substring(_ source : String, _ beginIndex : Int, _ endIndex : Int ) -> String{
        let subLen : Int = endIndex - beginIndex
        
        if(subLen < 0){
            return ""
        }
        let beginInx = source.index(source.startIndex, offsetBy: beginIndex)
        let endInx = source.index(source.startIndex, offsetBy: endIndex)
        let range = beginInx ..< endInx

        return String(source[range])
    }
    
    /// 網站已改用 UTF-8，先用 UTF-8 解碼；不是合法 UTF-8 時才用舊網頁的編碼（Big5 / GB2312）
    open class func dataToString(data : Data, fallbackEncoding : String.Encoding) -> String{
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = NSString(data: data, encoding: fallbackEncoding.rawValue) {
            return string as String
        }
        return ""
    }

    open class func dataToStringBig5(data : Data) -> String{
        return dataToString(data: data, fallbackEncoding: String.Encoding(rawValue: ENCODE_BIG5))
    }

    open class func dataToStringGB2312(data : Data) -> String{
        return dataToString(data: data, fallbackEncoding: String.Encoding(rawValue: ENCODE_GB2312))
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
        let encodeUrlString = source.data(using: String.Encoding(rawValue: encode), allowLossyConversion: true)
        
        return encodeUrlString!.hexEncodedString()
    }
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%%%02hhX", $0) }.joined()
    }
}
