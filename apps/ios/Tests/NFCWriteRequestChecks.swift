// Created by 이돈혁

import Foundation

@main
struct NFCWriteRequestChecks {
    static func main() throws {
        let links = [
            "https://example.org/stories/plaque-1",
            "https://appclip.apple.com/id?p=com.example.Clip&plaque=one%2Ftwo&name=a+b",
            "https://appclip.apple.com/id?=com.example.Clip&promotion=WWDC23",
            "https://example.org/story%2Fone?item=a%26b&empty=&item=c#section",
            "https://example.org:443/stories/1",
            "https://[2001:db8::1]/stories/1",
            "HTTPS://example.org/stories/1"
        ]
        for link in links {
            let request = try NFCWriteRequest(link)
            precondition(request.url.absoluteString == link, "Invocation path and query must remain unchanged")
        }
        let padded = try NFCWriteRequest(" \n\thttps://example.org/stories/1\r\n ")
        precondition(padded.url.absoluteString == "https://example.org/stories/1", "Trim only surrounding whitespace")

        let invalidLinks = [
            "", " \n\t", "http://example.org/stories/1", "ftp://example.org/file",
            "example.org/stories/1", "/stories/1", "https://", "https:///stories/1",
            "https://?plaque=1", "https://user@example.org/stories/1",
            "https://user:password@example.org/stories/1", "https://@example.org/stories/1",
            "https://example.org/a b", "https://example.org/a\nb", "https://example.org/a\tb",
            "https://example.org/a\u{0000}b", "https://example.org/a\u{007F}b",
            "https://example.org/%", "https://example.org/%2", "https://example.org/%GG",
            "https://exa mple.org/1", "https://[invalid]/1", "https://[::::]/1",
            "https://[2001:db8::gg]/1", "https://example.org:70000/1", "https://example.org:0/1"
        ]
        for link in invalidLinks {
            do {
                _ = try NFCWriteRequest(link)
                preconditionFailure("Invalid invocation URL accepted: \(link.debugDescription)")
            } catch NFCWriteRequestError.invalidURL {
            }
        }
        precondition(NFCWriteRequestError.invalidURL.errorDescription?.isEmpty == false, "Validation must explain recovery")
        print("PASS: NFC invocation URL validation (\(links.count + 1) valid, \(invalidLinks.count) invalid), exact path/query preservation")
    }
}
