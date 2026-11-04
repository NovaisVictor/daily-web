import Foundation
import Testing

@testable import FeatureNotes

/// Cases from `tests/lib/markdown/editing.test.ts`. `a<b>c` means "b selected";
/// `a<>c` is the caret between a and c; `|` is the caret for Return.
@Suite struct MarkdownEditingTests {
  private func run(_ marked: String, _ action: MarkdownAction) -> String {
    let source = marked as NSString
    let start = source.range(of: "<").location
    let end = source.range(of: ">").location - 1
    let text = marked.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
    let edit = MarkdownEditing.format(text, selection: TextSelection(start: start, end: end), action: action)
    let next = MarkdownEditing.apply(edit, to: text) as NSString
    let s = edit.selection.start
    let e = edit.selection.end
    return next.substring(to: s) + "<" + next.substring(with: NSRange(location: s, length: e - s)) + ">"
      + next.substring(from: e)
  }

  private func enter(_ marked: String) -> String? {
    let caret = (marked as NSString).range(of: "|").location
    let text = marked.replacingOccurrences(of: "|", with: "")
    guard let edit = MarkdownEditing.continueList(text, selection: TextSelection(start: caret, end: caret)) else {
      return nil
    }
    let next = MarkdownEditing.apply(edit, to: text) as NSString
    return next.substring(to: edit.selection.start) + "|" + next.substring(from: edit.selection.start)
  }

  @Test func wrapsTheSelection() {
    #expect(run("um <dois> três", .bold) == "um **<dois>** três")
    #expect(run("a <>b", .bold) == "a **<negrito>**b")
    #expect(run("<>", .italic) == "_<itálico>_")
  }

  @Test func applyingAgainUnwraps() {
    #expect(run("um **<dois>** três", .bold) == "um <dois> três")
    #expect(run("~~<x>~~", .strike) == "<x>")
  }

  @Test func codeIsInlineOnOneLineAndABlockOnSeveral() {
    #expect(run("rode <npm test>", .code) == "rode `<npm test>`")
    #expect(run("<a\nb>", .code) == "```\n<a\nb>\n```")
    #expect(run("antes <x> depois", .codeBlock) == "antes \n```\n<x>\n```\n depois")
  }

  @Test func links() {
    #expect(run("veja <a doc>", .link) == "veja [a doc](<https://>)")
    #expect(run("<https://exemplo.com>", .link) == "[<texto>](https://exemplo.com)")
  }

  @Test func linePrefixes() {
    #expect(run("<um\ndois>", .bullet) == "<- um\n- dois>")
    #expect(run("<um\ndois\ntrês>", .ordered) == "<1. um\n2. dois\n3. três>")
    #expect(run("com<>prar pão", .task) == "- [ ] com<>prar pão")
    #expect(run("<- um\n- dois>", .bullet) == "<um\ndois>")
    #expect(run("## Tí<>tulo", .heading) == "Tí<>tulo")
    #expect(run("<1. um\n2. dois>", .ordered) == "<um\ndois>")
    #expect(run("<- [ ] a>", .bullet) == "- <- [ ] a>")
    #expect(run("fora\nde<>ntro\nfora", .quote) == "fora\n> de<>ntro\nfora")
    #expect(run("<um\n>dois", .bullet) == "- <um\n>dois")
  }

  @Test func offsetsAreUTF16LikeTheTextView() {
    #expect(run("🙂 <ok>", .bold) == "🙂 **<ok>**")
  }

  @Test func continuesLists() {
    #expect(enter("- um|") == "- um\n- |")
    #expect(enter("* um|") == "* um\n* |")
    #expect(enter("1. um\n2. dois|") == "1. um\n2. dois\n3. |")
    #expect(enter("- [x] feito|") == "- [x] feito\n- [ ] |")
    #expect(enter("- a\n  - b|") == "- a\n  - b\n  - |")
  }

  @Test func returnOnAnEmptyItemEndsTheList() {
    #expect(enter("- um\n- |") == "- um\n|")
    #expect(enter("- [ ] |") == "|")
  }

  @Test func leavesReturnAloneOutsideALedItem() {
    #expect(enter("texto|") == nil)
    #expect(enter("-sem espaço|") == nil)
    #expect(enter("-| um") == nil)
    #expect(MarkdownEditing.continueList("- um", selection: TextSelection(start: 2, end: 4)) == nil)
  }

  @Test func shortcutMap() {
    func key(_ k: String, shift: Bool = false, option: Bool = false, control: Bool = false, command: Bool = true)
      -> MarkdownAction?
    {
      MarkdownEditing.shortcut(key: k, command: command, shift: shift, option: option, control: control)
    }
    #expect(key("b") == .bold)
    #expect(key("i") == .italic)
    #expect(key("e") == .code)
    #expect(key("k") == .link)
    #expect(key("X", shift: true) == .strike)
    #expect(key("b", shift: true) == nil)
    #expect(key("b", option: true) == nil)
    #expect(key("b", command: false) == nil)
    #expect(key("e", control: true) == nil)
  }
}
