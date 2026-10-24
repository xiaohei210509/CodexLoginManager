function locateDictation(source) {
  var options = {ecmaVersion: "latest", sourceType: "module"};
  var lexer = acorn.tokenizer(source, options), recent = [], matches = [];
  var depth = 0, candidates = [];
  function key(p) {
    return !p.computed && p.type === "Property"
      ? (p.key.name || p.key.value) : null;
  }
  function literal(n) {
    if (n.type === "Literal") return n.value;
    if (n.type === "TemplateLiteral" && n.expressions.length === 0)
      return n.quasis[0].value.cooked;
  }
  // Tokenization avoids building a multi-million-node AST for an entire bundle.
  // Candidate values are still parsed with Acorn, never executed.
  for (;;) {
    var token = lexer.getToken();
    if (token.type.label === "eof") break;
    if (token.type.label === "{" && recent.length === 3 &&
        recent[2].type.label === ":" &&
        (recent[1].type.label === "name" || recent[1].type.label === "string") &&
        recent[1].value === "dictation" &&
        (recent[0].type.label === "{" || recent[0].type.label === ",")) {
      candidates.push({start: token.start, depth: depth + 1});
    }
    if (token.type.label === "{" || token.type.label === "${") depth++;
    if (token.type.label === "}") {
      if (candidates.length && candidates[candidates.length - 1].depth === depth) {
        var candidate = candidates.pop();
        var object = acorn.parseExpressionAt(source.slice(candidate.start, token.end), 0, options);
        if (object.type !== "ObjectExpression") throw Error("Dynamic dictation configuration");
        var props = object.properties;
        var policies = props.filter(function(p) { return key(p) === "accessPolicy"; });
        var flags = props.filter(function(p) { return key(p) === "requiresFirstPartyInference"; });
        if (policies.some(function(p) { return literal(p.value) === "workspace-dictation"; })) {
          if (policies.length !== 1 || flags.length !== 1 || props.some(function(p) {
            return p.type !== "Property" || p.computed || p.kind !== "init";
          })) throw Error("Ambiguous dictation configuration");
          var value = flags[0].value, enabled;
          if (value.type === "Literal" && typeof value.value === "boolean")
            enabled = value.value;
          else if (value.type === "UnaryExpression" && value.operator === "!" &&
                   value.argument.type === "Literal" &&
                   (value.argument.value === 0 || value.argument.value === 1))
            enabled = !value.argument.value;
          else throw Error("Dynamic dictation policy");
          matches.push({start: candidate.start + value.start, end: candidate.start + value.end, enabled: enabled});
        }
      }
      depth--;
    }
    recent.push(token);
    if (recent.length > 3) recent.shift();
  }
  return matches;
}
