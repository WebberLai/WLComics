//
//  JSnview.swift
//  Pods
//
//  解析每集(話)漫畫圖片下載網址
//  使用 JavaScriptCore 執行網站混淆 JS，直接產生圖片網址
//
//  Created by Ray on 2017/8/19.
//  Updated: 2026/03 - 使用 JSContext 適配 8comic.com 新版混淆格式
//

import Foundation
import JavaScriptCore

open class JSnview{
    private var mSource : String?
    private var mCh : Int?
    private var mChs : Int = 0
    private var mTi : Int = 0
    private var mPs : Int = 0
    private var mCs : String = ""
    private var mC : String = ""
    private var mChunkSize : Int = 50

    open func setSource(_ source : String){
        mSource = source
    }

    open func getCh() -> Int{ return mCh! }
    open func setCh(_ ch : String) -> Void{ mCh = Int(ch) }
    open func getChs() -> Int{ return mChs }
    open func setChs(_ chs : Int) -> Void{ mChs = chs }
    open func getTi() -> Int{ return mTi }
    open func setTi(_ ti : Int) -> Void{ mTi = ti }
    open func getCs() -> String{ return mCs }
    open func setCs(_ cs : String) -> Void{ mCs = cs }
    open func setChunkSize(_ size : Int) -> Void{ mChunkSize = size }

    /// 建立 JSContext 並設定所有 mock 和 helper functions
    private func createContext(ch: Int, pg: Int) -> JSContext? {
        guard let ctx = JSContext() else { return nil }

        ctx.exceptionHandler = { _, exception in
            print("JSnview JSError: \(exception?.toString() ?? "unknown")")
        }

        // nview.js helper functions
        ctx.evaluateScript("""
            function nn(n){return n<10?'00'+n:n<100?'0'+n:n;}
            function mm(p){return (parseInt((p-1)/10)%10)+(((p-1)%10)*3);}
            function lc(l){if(l.length!=2)return l;var az="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";var a=l.substring(0,1);var b=l.substring(1,2);if(a=="Z")return 8000+az.indexOf(b);else return az.indexOf(a)*52+az.indexOf(b);}
            function ss(a,b,c,d){var e=(a+'').substring(b,b+c);return d==null?e.replace(/[a-z]*/gi,""):e;}
        """)

        // 完整的瀏覽器 API mock
        let chStr = pg > 1 ? "\(ch)-\(pg)" : "\(ch)"
        ctx.evaluateScript("""
            var capturedSrc = '';
            var _mockElement = {
                _src: '',
                get src() { return this._src; },
                set src(v) { this._src = v; capturedSrc = v; },
                style: { display: '', visibility: '' },
                innerHTML: '', innerText: '', value: '',
                href: '', className: '', id: '',
                onclick: null, onload: null,
                setAttribute: function(){},
                getAttribute: function(){ return ''; },
                appendChild: function(){},
                removeChild: function(){}
            };
            var document = {
                getElementById: function(id) { return _mockElement; },
                getElementsByTagName: function(tag) { return []; },
                getElementsByClassName: function(cls) { return []; },
                querySelector: function(sel) { return _mockElement; },
                querySelectorAll: function(sel) { return []; },
                createElement: function(tag) { return _mockElement; },
                title: '', cookie: '',
                write: function(){}, writeln: function(){},
                location: { href: '', search: '?ch=\(chStr)', hash: '', pathname: '' }
            };
            var window = {
                location: document.location,
                navigator: { userAgent: 'Mozilla/5.0' },
                setTimeout: function(fn, ms) { fn(); },
                setInterval: function(){},
                innerWidth: 1024, innerHeight: 768,
                open: function(){ return {}; }
            };
            var navigator = window.navigator;
            var location = document.location;
            var Image = function(){ return _mockElement; };
            var XMLHttpRequest = function(){ return { open:function(){}, send:function(){}, setRequestHeader:function(){} }; };
            function alert(msg){}
            function confirm(msg){ return true; }
            function prompt(msg){ return ''; }
            function ge(id) { return document.getElementById(id); }
            function request(key) { return '\(chStr)'; }
        """)

        return ctx
    }

    //讀取1話(集、卷)全部漫畫圖片網址
    open func setupPagesDownloadUrl() -> [String]{
        guard let ch = mCh else {
            print("JSnview: mCh is nil")
            return []
        }
        guard let source = mSource, !source.isEmpty else {
            print("JSnview: source is nil or empty")
            return []
        }

        print("JSnview: ch=\(ch), ti=\(mTi), source length=\(source.count)")

        // 第一次執行：取得總頁數
        guard let ctx = createContext(ch: ch, pg: 1) else {
            print("JSnview: failed to create JSContext")
            return []
        }

        ctx.evaluateScript(source)

        let ps = ctx.evaluateScript("ps")?.toInt32() ?? 0
        let firstUrl = ctx.evaluateScript("capturedSrc")?.toString() ?? ""

        print("JSnview: ps=\(ps), firstUrl=\(firstUrl)")

        guard ps > 0 else {
            print("JSnview: page count is 0")
            return []
        }

        // 收集所有頁的 URL
        var urls = [String]()

        // 加入第一頁
        if !firstUrl.isEmpty && firstUrl != "undefined" {
            let fullUrl = firstUrl.hasPrefix("//") ? "https:" + firstUrl : firstUrl
            urls.append(fullUrl)
        }

        // 產生第2頁到最後一頁的 URL
        // 每頁建立獨立 JSContext 執行，確保乾淨狀態
        for p in 2...Int(ps) {
            autoreleasepool {
                guard let pCtx = createContext(ch: ch, pg: p) else { return }
                pCtx.evaluateScript(source)

                if let url = pCtx.evaluateScript("capturedSrc")?.toString(),
                   !url.isEmpty, url != "undefined" {
                    let fullUrl = url.hasPrefix("//") ? "https:" + url : url
                    urls.append(fullUrl)
                }
            }
        }

        print("JSnview: generated \(urls.count) URLs for \(ps) pages")
        if let first = urls.first {
            print("JSnview: first = \(first)")
        }
        if let last = urls.last, urls.count > 1 {
            print("JSnview: last = \(last)")
        }

        return urls
    }
}
