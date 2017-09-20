//
//  JSnview.swift
//  Pods
//
//  解析每集(話)漫畫圖片下載網址
//
//  Created by Ray on 2017/8/19.
//
//

import Foundation
import JavaScriptCore

open class JSnview{
    fileprivate var mSource : String?
    fileprivate var mCh : Int?
    fileprivate var mChs : Int = 0
    fileprivate var mTi : Int = 0
    fileprivate var mPs : Int = 0 //漫畫總頁數
    fileprivate var mCs : String = ""
    fileprivate var mC : String = ""
    fileprivate static let Y : Int = 46;
    
    open func setSource(_ source : String){
        mSource = source
    }
    
    /*
     * 取得集數編號，例如1、2、3…
     */
    open func getCh() -> Int{
        return mCh!
    }
    
    open func setCh(_ ch : String) -> Void{
        mCh = Int(ch)
    }
    
    /*
     * 取得最新集數，例如最新第68號，此回傳值則為68
     */
    open func getChs() -> Int{
        return mChs
    }
    
    open func setChs(_ chs : Int) -> Void{
        mChs = chs
    }
    
    open func getTi() -> Int{
        return mTi
    }
    
    open func setTi(_ ti : Int) -> Void{
        mTi = ti
    }
    
    /*
     * 取得單集漫畫混淆過的編碼
     */
    open func getCs() -> String{
        return mCs
    }
    
    open func setCs(_ cs : String) -> Void{
        mCs = cs
    }
    
    //讀取1話(集、卷)全部漫畫圖片網址
    open func setupPagesDownloadUrl() -> [String]{
        return invokeJS(mSource!, JSnview.Y, mCh!)
    }
    
    open func invokeJS(_ js : String, _ y : Int, _ ch : Int) -> [String]{
        let context = JSContext()!
        var str : String = StringUtility.substring(js, 0, StringUtility.indexOfInt(js, "var pt="))
        str = StringUtility.replace(str, "ge('TheImg').src", "var src")
        let unuseScript : String = StringUtility.substring(str, "\'.jpg\';", "break;")!
        str = StringUtility.replace(str, unuseScript, "")
        let varSrc : String = StringUtility.substring(str, "ci = i; ", "break;")!
        let getPageJS : String = String.init(format: buildGetPagesJS(), varSrc)
        str = StringUtility.replace(str, varSrc, "")
        str = StringUtility.replace(str, "break;", getPageJS)
        let script : String = "function sp2(ch, y){" + str + "} " + buildNviewJS()
        
        context.evaluateScript(script)
        
        //取出funciton sp2()
        let sp2Function = context.objectForKeyedSubscript("sp2")
        //呼叫javsccript的 sp2() function
        let jsvalue : JSValue = (sp2Function?.call(withArguments: [ch, y]))!
        let list = jsvalue.toArray() as! [String]
        
        return list;
    }
    
    fileprivate func buildGetPagesJS() -> String{
        var buf : String = String();
        
        buf.append("var result = [];")
        buf.append("for(var p = 1; p <= ps; p++){")
        buf.append("%@")
        buf.append("result.push(src);")
        buf.append("}")
        buf.append("return result;")
        
        return buf;
    }
    
    fileprivate func buildNviewJS() -> String{
        var buf : String = String();
        
        buf.append("function lc(l) {")
        buf.append("if (l.length != 2) return l;")
        buf.append("var az = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\";")
        buf.append("var a = l.substring(0, 1);")
        buf.append("var b = l.substring(1, 2);")
        buf.append("if (a == \"Z\") return 8000 + az.indexOf(b);")
        buf.append("else return az.indexOf(a) * 52 + az.indexOf(b);}")
        
        buf.append("function su(a, b, c) {")
        buf.append("var e = (a + '').substring(b, b + c);")
        buf.append("return (e);")
        buf.append("}")
        
        buf.append("function nn(n) {")
        buf.append("return n < 10 ? '00' + n : n < 100 ? '0' + n : n;")
        buf.append("}")
        
        buf.append("function mm(p) {")
        buf.append("return (parseInt((p - 1) / 10) % 10) + (((p - 1) % 10) * 3)")
        buf.append("}")
        
        return buf;
    }

    
}
