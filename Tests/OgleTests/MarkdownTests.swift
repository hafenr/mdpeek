import XCTest
@testable import Ogle

final class MarkdownTests: XCTestCase {
    func testFrontMatterIsATableAndTheLinesAfterItKeepTheirNumbers() {
        let markdown = """
            ---
            title: A <b> & "c"
            authors: [x, y]
            nested:
              owner: z
            ---

            # Title
            """
        XCTAssertEqual(
            Markdown.html(from: Data(markdown.utf8)),
            #"<table class="front-matter" data-sourcepos="1:1-6:3"><tbody>"#
                + #"<tr><th>title</th><td>A &lt;b&gt; &amp; &quot;c&quot;</td></tr>"#
                + "<tr><th>authors</th><td><table><tbody><tr><td>x</td><td>y</td></tr></tbody></table></td></tr>"
                + "<tr><th>nested</th><td><table><thead><tr><th>owner</th></tr></thead>"
                + "<tbody><tr><td>z</td></tr></tbody></table></td></tr>"
                + "</tbody></table>\n"
                + #"<h1 data-sourcepos="8:1-8:7">Title</h1>"# + "\n")
    }

    func testFrontMatterLinksURLs() {
        let markdown = "---\nticket: see https://example.com/a?b=1&c=2\n---\n"
        XCTAssertEqual(
            Markdown.html(from: Data(markdown.utf8)),
            #"<table class="front-matter" data-sourcepos="1:1-3:3"><tbody><tr><th>ticket</th><td>see "#
                + #"<a href="https://example.com/a?b=1&amp;c=2">https://example.com/a?b=1&amp;c=2</a>"#
                + "</td></tr></tbody></table>\n")
    }

    func testFrontMatterEndsAtDotsAndWorksWithWindowsLineEndings() {
        let markdown = "---\r\ntitle: T\r\n...\r\n# H\r\n"
        XCTAssertEqual(
            Markdown.html(from: Data(markdown.utf8)),
            #"<table class="front-matter" data-sourcepos="1:1-3:3"><tbody><tr><th>title</th><td>T</td></tr></tbody></table>"#
                + "\n" + #"<h1 data-sourcepos="4:1-4:3">H</h1>"# + "\n")
    }

    func testInvalidYAMLIsLeftToMarkdown() {
        let markdown = "---\ntitle: \"unclosed\n---\n"
        XCTAssertEqual(
            Markdown.html(from: Data(markdown.utf8)),
            #"<hr data-sourcepos="1:1-1:3" />"# + "\n" + #"<h2 data-sourcepos="2:1-3:3">title: &quot;unclosed</h2>"# + "\n")
    }

    func testARuleAboveProseIsNotFrontMatter() {
        let markdown = "---\n\nText\n\n---\n"
        XCTAssertEqual(
            Markdown.html(from: Data(markdown.utf8)),
            #"<hr data-sourcepos="1:1-2:0" />"# + "\n" + #"<p data-sourcepos="3:1-3:4">Text</p>"# + "\n"
                + #"<hr data-sourcepos="5:1-5:3" />"# + "\n")
    }
}
