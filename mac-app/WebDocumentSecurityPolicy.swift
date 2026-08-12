import Foundation

enum WebDocumentSecurityPolicy {
    static let contentSecurityPolicy = [
        "default-src 'none'",
        "img-src file: data:",
        "style-src 'unsafe-inline'",
        "font-src file: data:",
        "media-src file: data:",
        "connect-src 'none'",
        "frame-src 'none'",
        "form-action 'none'",
        "base-uri 'none'",
        "object-src 'none'"
    ].joined(separator: "; ")

    static let DOMSanitizerScript = #"""
    (() => {
      const allowedTags = new Set([
        "A", "ABBR", "ADDRESS", "ARTICLE", "ASIDE", "B", "BDI", "BDO",
        "BLOCKQUOTE", "BR", "CAPTION", "CITE", "CODE", "COL", "COLGROUP",
        "DD", "DEL", "DFN", "DIV", "DL", "DT", "EM", "FIGCAPTION", "FIGURE",
        "H1", "H2", "H3", "H4", "H5", "H6", "HR", "I", "IMG", "INS", "KBD",
        "LI", "MAIN", "MARK", "NAV", "OL", "P", "PRE", "Q", "RP", "RT", "RUBY",
        "S", "SAMP", "SECTION", "SMALL", "SPAN", "STRONG", "SUB", "SUP",
        "TABLE", "TBODY", "TD", "TFOOT", "TH", "THEAD", "TIME", "TR", "U",
        "UL", "VAR", "WBR", "SVG", "G", "PATH", "RECT", "CIRCLE", "ELLIPSE",
        "LINE", "POLYLINE", "POLYGON", "TEXT", "TSPAN", "USE"
      ]);
      const globalAttributes = new Set([
        "class", "id", "lang", "xml:lang", "dir", "title", "role",
        "aria-label", "aria-hidden", "tabindex", "style"
      ]);
      const perTagAttributes = {
        A: new Set(["href", "name"]),
        IMG: new Set(["src", "alt", "width", "height", "loading"]),
        COL: new Set(["span", "width"]),
        COLGROUP: new Set(["span", "width"]),
        TD: new Set(["colspan", "rowspan", "headers"]),
        TH: new Set(["colspan", "rowspan", "headers", "scope"]),
        OL: new Set(["start", "reversed", "type"]),
        LI: new Set(["value"]),
        Q: new Set(["cite"]),
        BLOCKQUOTE: new Set(["cite"]),
        TIME: new Set(["datetime"]),
        SVG: new Set(["viewbox", "width", "height", "preserveaspectratio"]),
        USE: new Set(["href", "xlink:href"]),
        PATH: new Set(["d", "fill", "stroke"]),
        G: new Set(["fill", "stroke", "transform"]),
        RECT: new Set(["x", "y", "width", "height", "rx", "ry", "fill", "stroke"]),
        CIRCLE: new Set(["cx", "cy", "r", "fill", "stroke"]),
        ELLIPSE: new Set(["cx", "cy", "rx", "ry", "fill", "stroke"]),
        LINE: new Set(["x1", "y1", "x2", "y2", "stroke"]),
        POLYLINE: new Set(["points", "fill", "stroke"]),
        POLYGON: new Set(["points", "fill", "stroke"]),
        TEXT: new Set(["x", "y", "fill", "text-anchor"]),
        TSPAN: new Set(["x", "y", "dx", "dy"])
      };
      const allowedURL = (value, attribute) => {
        const compact = value.replace(/[\u0000-\u0020\u007f]+/g, "");
        let parsed;
        try { parsed = new URL(compact, document.baseURI); } catch (_) { return false; }
        const scheme = parsed.protocol.toLowerCase();
        if (attribute === "href" && (scheme === "http:" || scheme === "https:")) return true;
        if (scheme === "file:") {
          const base = new URL(".", document.baseURI);
          const root = base.pathname.endsWith("/") ? base.pathname : base.pathname + "/";
          return parsed.pathname === base.pathname || parsed.pathname.startsWith(root);
        }
        if (scheme === "about:" && parsed.hash) return true;
        return attribute === "src" && scheme === "data:" && /^data:image\//i.test(compact);
      };
      const sanitizeElement = element => {
        const tagName = element.tagName.toUpperCase();
        if (!allowedTags.has(tagName)) {
          element.replaceWith(...element.childNodes);
          return;
        }
        const tagAttributes = perTagAttributes[tagName] || new Set();
        for (const attribute of Array.from(element.attributes)) {
          const name = attribute.name.toLowerCase();
          const isData = name.startsWith("data-leaf-") || name.startsWith("data-reader-");
          const isAllowed = globalAttributes.has(name) || tagAttributes.has(name) || isData;
          if (!isAllowed || name.startsWith("on") || name === "srcset") {
            element.removeAttribute(attribute.name);
            continue;
          }
          if (name === "style" && /(?:url\s*\(|@import|expression\s*\()/i.test(attribute.value)) {
            element.removeAttribute(attribute.name);
          } else if ((name === "href" || name === "src" || name === "xlink:href") &&
                     !allowedURL(attribute.value, name === "xlink:href" ? "href" : name)) {
            element.removeAttribute(attribute.name);
          }
        }
      };
      const sanitizeTree = root => {
        if (root.nodeType === Node.ELEMENT_NODE) sanitizeElement(root);
        if (root.querySelectorAll) Array.from(root.querySelectorAll("*")).forEach(sanitizeElement);
      };
      const observer = new MutationObserver(records => {
        for (const record of records) {
          for (const node of record.addedNodes) sanitizeTree(node);
        }
      });
      const begin = () => {
        if (!document.body) return;
        sanitizeTree(document.body);
        observer.observe(document.body, { childList: true, subtree: true });
      };
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", begin, { once: true });
      } else {
        begin();
      }
    })();
    """#
}

enum WebDocumentNavigationDecision: Equatable {
    case allow
    case cancel
    case openExternally
    case scrollToFragment(String)
}

enum WebDocumentNavigationPolicy {
    static func decision(
        for url: URL,
        isUserActivatedLink: Bool,
        isApprovedInitialNavigation: Bool
    ) -> WebDocumentNavigationDecision {
        if isUserActivatedLink {
            if url.scheme == "http" || url.scheme == "https" {
                return .openExternally
            }
            if let fragment = url.fragment, !fragment.isEmpty {
                return .scrollToFragment(fragment)
            }
            return .cancel
        }
        if isApprovedInitialNavigation, url.isFileURL || url.absoluteString == "about:blank" {
            return .allow
        }
        return .cancel
    }
}
