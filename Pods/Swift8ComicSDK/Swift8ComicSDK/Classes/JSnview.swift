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
    private var mSource : String?
    private var mCh : Int?
    private var mChs : Int = 0
    private var mTi : Int = 0
    private var mPs : Int = 0 //漫畫總頁數
    private var mCs : String = ""
    private var mC : String = ""
    private static let Y : Int = 46;

    open func setSource(_ source : String){
        mSource = source
    }

    /*
     * 取得集數編號，例如1、2、3…
     */
    open func getCh() -> Int{
        return mCh ?? 0
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
        guard let source = mSource, let ch = mCh else {
            print("[DEBUG] JSnview: mSource 或 mCh 為 nil, mSource=\(mSource != nil), mCh=\(mCh != nil)")
            return []
        }

        // 判斷新舊格式
        if source.range(of: ".src=unescape(") != nil {
            return invokeJSNew(source, ch)
        } else {
            return invokeJS(source, JSnview.Y, ch)
        }
    }

    // 新格式：混淆過的 JS，用 JSContext 直接執行
    open func invokeJSNew(_ js: String, _ ch: Int) -> [String] {
        guard let context = JSContext() else {
            print("[DEBUG] JSnview: JSContext 建立失敗")
            return []
        }

        // 1. 提供 nview.js 的 helper functions
        context.evaluateScript(buildNviewJS())

        // 2. 修改 source JS
        var modJS = js

        // 替換 request('ch') 為實際的 ch 值
        modJS = modJS.replacingOccurrences(of: "request('ch')", with: "'\(ch)'")
        modJS = modJS.replacingOccurrences(of: "request(\"ch\")", with: "'\(ch)'")

        // 3. 找到 ge(...).src=unescape(EXPR);; 並替換為收集所有頁面 URL 的迴圈
        guard let srcAssignRange = modJS.range(of: ".src=unescape(", options: .backwards) else {
            print("[DEBUG] JSnview: 找不到 .src=unescape(")
            return []
        }

        // 找到 ge( 的位置（在 .src= 之前）
        let beforeSrc = String(modJS[modJS.startIndex..<srcAssignRange.lowerBound])
        guard let geRange = beforeSrc.range(of: "ge(", options: .backwards) else {
            print("[DEBUG] JSnview: 找不到 ge(")
            return []
        }

        // 提取 unescape(...) 裡的表達式
        let exprStartIndex = srcAssignRange.upperBound
        let afterUnescape = String(modJS[exprStartIndex...])

        // 從尾端找到 );; 作為結束
        guard let closingRange = afterUnescape.range(of: ");;", options: .backwards) else {
            print("[DEBUG] JSnview: 找不到 );;")
            return []
        }
        let unescapeExpr = String(afterUnescape[afterUnescape.startIndex..<closingRange.lowerBound])

        // 4. 組合修改後的 JS
        // prefix = 原始 JS 中 ge(...) 之前的所有程式碼（包含 ch 解析、for 迴圈找 chapter、設定 ps 等）
        let prefix = String(modJS[modJS.startIndex..<geRange.lowerBound])

        // 迴圈收集所有頁面的圖片 URL，補上 https: 前綴
        let loopJS = """
        var __urls = [];
        for (var __p = 1; __p <= ps; __p++) {
            pg = __p;
            var __u = unescape(\(unescapeExpr));
            if (__u.indexOf('//') === 0) __u = 'https:' + __u;
            __urls.push(__u);
        }
        """

        let fullScript = prefix + loopJS

        // 5. 執行
        context.exceptionHandler = { _, exception in
            print("[DEBUG] JSnview JSContext error: \(exception?.toString() ?? "unknown")")
        }

        context.evaluateScript(fullScript)

        guard let urls = context.objectForKeyedSubscript("__urls")?.toArray() as? [String] else {
            print("[DEBUG] JSnview: 無法取得 __urls")
            return []
        }

        return urls
    }

    // 舊格式
    open func invokeJS(_ js : String, _ y : Int, _ ch : Int) -> [String]{
        guard let context = JSContext() else { return [] }

        guard StringUtility.indexOf(source: js, search: "var pt=") != nil else {
            print("[DEBUG] JSnview: 舊格式找不到 var pt=")
            return []
        }

        var str : String = StringUtility.substring(js, 0, StringUtility.indexOfInt(js, "var pt="))
        str = StringUtility.replace(str, "ge('TheImg').src", "var src")

        guard let unuseScript = StringUtility.substring(str, "\'.jpg\';", "break;") else {
            print("[DEBUG] JSnview: 舊格式找不到 .jpg/break 標記")
            return []
        }
        str = StringUtility.replace(str, unuseScript, "")

        var varSrc : String

        if StringUtility.indexOf(source: str, search: "ci=i;") != nil {
            varSrc = StringUtility.substring(str, "ci=i;", "break;") ?? ""
        } else {
            varSrc = StringUtility.substring(str, "ci = i;", "break;") ?? ""
        }

        guard !varSrc.isEmpty else {
            print("[DEBUG] JSnview: 舊格式找不到 ci=i 標記")
            return []
        }

        varSrc = StringUtility.replace(str, "//img", "https://img")

        let getPageJS : String = String.init(format: buildGetPagesJS(), varSrc)
        str = StringUtility.replace(str, varSrc, "")
        str = StringUtility.replace(str, "break;", getPageJS)
        let script : String = "function sp2(ch, y){" + str + "} " + buildNviewJS()

        context.evaluateScript(script)

        let sp2Function = context.objectForKeyedSubscript("sp2")
        guard let jsvalue = sp2Function?.call(withArguments: [ch, y]),
              let list = jsvalue.toArray() as? [String] else {
            print("[DEBUG] JSnview: 舊格式 sp2() 執行失敗")
            return []
        }

        return list
    }

    private func buildGetPagesJS() -> String{
        var buf : String = String();

        buf.append("var result = [];")
        buf.append("for(var p = 1; p <= ps; p++){")
        buf.append("%@")
        buf.append("result.push(src);")
        buf.append("}")
        buf.append("return result;")

        return buf;
    }

    private func buildNviewJS() -> String{
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
