import Foundation

/// Minimalne drzewo XML świadome przestrzeni nazw, z wyszukiwaniem ścieżek
/// w semantyce ElementTree (`find('.//a/b')`, `find('a/b')`, `findall`).
/// Foundation na iOS nie ma `XMLDocument`, a parser FA potrzebuje tylko
/// prostych ścieżek, więc budujemy własne drzewo na `XMLParser`.
final class XMLNode {
    let namespace: String
    let name: String
    /// Odpowiednik `element.text` w lxml: tekst przed pierwszym dzieckiem.
    fileprivate(set) var text: String = ""
    fileprivate(set) var children: [XMLNode] = []
    fileprivate(set) var attributes: [String: String] = [:]
    fileprivate var sawChild = false

    init(namespace: String, name: String) {
        self.namespace = namespace
        self.name = name
    }

    /// Pierwszy element pasujący do ścieżki. Ścieżka to nazwy lokalne
    /// rozdzielone `/`, opcjonalnie poprzedzone `.//` (dowolny potomek).
    func find(_ path: String, ns: String) -> XMLNode? {
        var first: XMLNode?
        visit(path, ns: ns) { first = $0; return false }
        return first
    }

    func findAll(_ path: String, ns: String) -> [XMLNode] {
        var all: [XMLNode] = []
        visit(path, ns: ns) { all.append($0); return true }
        return all
    }

    /// `(node.text or '').strip()` dla pierwszego dopasowania, "" gdy brak.
    func text(_ path: String, ns: String) -> String {
        guard let node = find(path, ns: ns) else { return "" }
        return PyText.strip(node.text)
    }

    private func visit(_ path: String, ns: String, _ yield: (XMLNode) -> Bool) {
        let descendant = path.hasPrefix(".//")
        let steps = (descendant ? String(path.dropFirst(3)) : path).split(separator: "/").map(String.init)
        guard let head = steps.first else { return }
        let rest = Array(steps.dropFirst())
        let starts: [XMLNode] = descendant
            ? descendants().filter { $0.matches(head, ns) }
            : children.filter { $0.matches(head, ns) }
        for start in starts {
            if !Self.walk(start, rest, ns, yield) { return }
        }
    }

    /// Zwraca false, gdy wywołujący chce przerwać przeszukiwanie.
    private static func walk(_ node: XMLNode, _ steps: [String], _ ns: String, _ yield: (XMLNode) -> Bool) -> Bool {
        guard let head = steps.first else { return yield(node) }
        let rest = Array(steps.dropFirst())
        for child in node.children where child.matches(head, ns) {
            if !walk(child, rest, ns, yield) { return false }
        }
        return true
    }

    private func matches(_ localName: String, _ ns: String) -> Bool {
        name == localName && namespace == ns
    }

    /// Wszyscy potomkowie w kolejności dokumentu, bez samego węzła.
    func descendants() -> [XMLNode] {
        var out: [XMLNode] = []
        func go(_ n: XMLNode) { for c in n.children { out.append(c); go(c) } }
        go(self)
        return out
    }
}

/// Wynik parsowania: korzeń i przestrzenie nazw zadeklarowane w dokumencie.
struct XMLTree {
    let root: XMLNode
    let declaredNamespaces: [String]

    static func parse(_ data: Data) -> XMLTree? {
        let delegate = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.failed == false, let root = delegate.root else { return nil }
        return XMLTree(root: root, declaredNamespaces: delegate.namespaces)
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLNode?
        var stack: [XMLNode] = []
        var namespaces: [String] = []
        var failed = false

        func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
            namespaces.append(namespaceURI)
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLNode(namespace: namespaceURI ?? "", name: elementName)
            node.attributes = attributeDict
            if let parent = stack.last {
                parent.children.append(node)
                parent.sawChild = true
            } else {
                root = node
            }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            _ = stack.popLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard let current = stack.last, !current.sawChild else { return }
            current.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let current = stack.last, !current.sawChild else { return }
            current.text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            failed = true
        }
    }
}
