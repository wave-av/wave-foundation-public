// copy-grammar-rules.mjs — the rule set behind check-copy-grammar.mjs (vocabulary, regexes, checks).
// SSOT: wave-foundation frameworks/copywriting/copy-grammar-rules.mjs; consumer repos carry a
// byte-identical copy next to their scripts/check-copy-grammar.mjs. Edit here, then re-vendor.
// Every rule cites the live receipt that motivated it; a rule without a receipt does not ship.

// ── Vocabulary ──────────────────────────────────────────────────────────────────────────────────

// Acronyms and brand tokens that are legitimately ALL-CAPS in copy. A CTA made ONLY of these
// ("SDK EULA", "DMCA") is a name, not a shouted label. HTTP verbs cover reference copy.
const ACRONYMS = new Set([
  "WAVE", "API", "SDK", "MCP", "CLI", "SRT", "RTMP", "RTMPS", "HLS", "DASH", "WHIP", "WHEP", "WEBRTC",
  "MOQ", "NDI", "OMT", "AES67", "ST", "2110", "SMPTE", "DANTE", "OG", "SEO", "EULA", "DMCA", "GDPR",
  "CCPA", "HIPAA", "DPA", "BAA", "SLA", "SOC", "ISO", "PCI", "DSS", "TOS", "FAQ", "URL", "URI", "ID",
  "IDS", "JSON", "YAML", "HTML", "CSS", "HTTP", "HTTPS", "TLS", "SSL", "DNS", "CDN", "IP", "TCP", "UDP",
  "QUIC", "AV", "AV1", "H264", "H265", "HEVC", "VP9", "AAC", "OPUS", "PCM", "MP4", "MP3", "WEBM", "TTS",
  "STT", "ASR", "LLM", "AI", "GPU", "CPU", "RAM", "SSD", "US", "EU", "UK", "USD", "EUR", "GBP", "USDC",
  "ETH", "MPP", "X402", "DID", "JWT", "OAUTH", "SSO", "SAML", "SCIM", "MFA", "2FA", "OTP", "PR", "CI",
  "CD", "QA", "UI", "UX", "A11Y", "I18N", "L10N", "RSS", "ATOM", "XML", "PDF", "CSV", "SVG", "PNG", "JPG",
  "GIF", "WEBP", "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "OK", "N/A", "TBD", "ASAP",
  "LLC", "INC", "LTD", "VOD", "OTT", "IRL", "AM", "PM", "UTC", "EST", "EDT", "PST", "PDT", "PT", "ET",
  "V1", "V2", "V3", "GA", "MVP", "SLO", "SLI", "OKR", "KPI", "ROI", "COGS", "ARR", "MRR", "NPS", "IO",
]);

// A shouted label is only judged when it contains an ordinary English word — "SDI · HDMI" is a list
// of acronyms, "GET API KEY" contains GET and KEY. Strings carrying code characters are skipped.
const CAPS_TELLS = new Set(("GET YOUR THE A AN TO KEY KEYS NOW START STARTED SIGN LOG IN UP OUT WHAT YOU FREE TRY READ MORE " +
  "DOCS CALL TALK SALES BOOK DEMO CREATE ACCOUNT TOUCH LEARN VIEW OPEN BUILD SEE GO ADD PAY WATCH LIVE STREAM PLAY " +
  "JOIN CONTINUE BACK NEXT SUBMIT SEND SAVE CANCEL CLOSE DONE APPLY CONNECT DOWNLOAD UPLOAD COPY PASTE SHARE EXPLORE " +
  "DISCOVER REQUEST CONTACT PRICING PLANS PLAN UPGRADE BUY ORDER CHECKOUT SUBSCRIBE FOLLOW WITH FOR AND OR OF ON").split(" "));

// After "kinds of / types of / sorts of" the head noun is plural. These are the count nouns that
// appear in WAVE copy; a noun outside the list is not judged (fail-quiet on vocabulary, fail-loud
// on the shapes we have actually shipped wrong).
const COUNT_NOUNS =
  "user|agent|person|caller|customer|developer|buyer|builder|creator|viewer|team|company|partner|" +
  "transport|codec|protocol|model|engine|call|stream|key|route|surface|repo|worker|request|response|" +
  "event|error|plan|tier|rail|receipt|payment|wallet|card|account|session|room|track|clip|file|" +
  "format|device|screen|page|link|button|field|option|setting|limit|region|endpoint|token|credential";
const COUNT_NOUN_RE = new RegExp(`\\b(kinds|types|sorts) of (${COUNT_NOUNS})(?![\\w'’-])`, "gi");
// "two X", "both X", "many X" — only when the noun is followed by punctuation, end-of-string, or a
// function word. "both user and agent traffic" (adjectival) is legal and stays quiet.
const QUANT_NOUN_RE = new RegExp(
  `\\b(two|three|four|five|both|many|several|multiple|dozens of|hundreds of) (${COUNT_NOUNS})` +
    `(?=[,.;:!?)]|$|\\s+(?:of|on|in|to|at|for|with|from|that|who|which|now|today)\\b)`,
  "gi",
);

// "login/signup/setup/checkout" are nouns; the verbs are two words. Flag the one-word form after a
// verb-taking word, and the two-word form used as a modifier of a noun ("sign in page").
const VERB_LEAD =
  "to|can|cannot|can't|please|and|or|then|you|users?|agents?|people|must|should|will|may|now|" +
  "again|first|also|already|simply|when you|if you|before you|after you";
const NOUN_AS_VERB_RE = new RegExp(
  `\\b(?:${VERB_LEAD}) (login|logout|signin|signup|setup|checkout|sign-in|sign-up|log-in|log-out|set-up)\\b`,
  "gi",
);
const VERB_AS_NOUN_RE =
  /\b(log in|log out|sign in|sign up|set up|check out) (page|form|button|link|flow|screen|process|step|url|route|modal|dialog|panel|email|code)\b/gi;

// Missing serial comma in a three-item list whose items are lowercase words. The lowercase gate
// keeps "At WAVE, people and agents pay" (a clause, not a list) quiet. WARN — style consistency.
const OXFORD_RE = /\b[a-z][\w-]*, [a-z][\w-]* (?:and|or) [a-z][\w-]*(?![\w-]*,)/g;

// Words that, capitalised mid-label, mark Title Case rather than a proper noun. "Get API Key" fails
// on "Key"; "The Money Engine" (a product name) passes because "Money"/"Engine" are not listed.
const TITLE_CASE_TELLS = new Set([
  "A", "An", "The", "Your", "My", "Our", "To", "For", "With", "In", "On", "And", "Or", "Of", "Key",
  "Keys", "Started", "Sales", "Docs", "Now", "Free", "Account", "More", "Call", "Demo", "Started",
  "Up", "Out", "Back", "Next", "Continue", "Pricing", "Plan", "Plans", "Trial", "Access", "Started",
]);

// Contexts that mark a string as a CTA/label (Title Case rule applies only here).
export const LABEL_KEY_RE = /\b(label|primaryLabel|salesLabel|secondaryLabel|ctaLabel|buttonLabel|buttonText|aria-label|ariaLabel|cta)\s*[:=]\s*$/;

// ── Rules ───────────────────────────────────────────────────────────────────────────────────────

/** @type {Record<string, {severity:"error"|"warn", summary:string, receipt:string}>} */
export const RULES = {
  "count-noun-agreement": {
    severity: "error",
    summary: "count noun after 'kinds of / types of / two / both / many' must be plural",
    receipt: "wave.online hero kicker 2026-09-03: 'Built for two kinds of user: people and agents'",
  },
  "cta-caps": {
    severity: "error",
    summary: "labels are sentence case — no ALL-CAPS, no Title Case (voice-and-tone.md: buttons are sentence case)",
    receipt: "Jake 2026-09-03: 'GET API KEY'; console.wave.online/signup literal 'WHAT YOU GET'",
  },
  "api-term-case": {
    severity: "error",
    summary: "'API' is capitalised as a term ('api' is only ever a path segment or identifier)",
    receipt: "voice-and-tone.md glossary; the nav CTA renders 'Get an API key'",
  },
  "login-verb-noun": {
    severity: "error",
    summary: "'log in' / 'sign in' are verbs (two words); 'login' / 'sign-in' are nouns and modifiers",
    receipt: "console copy audit 2026-09-03: 'Sign in' (verb) vs 'sign-in page' (modifier)",
  },
  "oxford-comma": {
    severity: "warn",
    summary: "three-item lists carry the serial comma (WAVE house style; measured 0 exceptions in shipped copy)",
    receipt: "private-repo content/*.ts 2026-09-03: every 3-item list uses 'a, b, and c'",
  },
  "double-space": {
    severity: "error",
    summary: "no double spaces inside copy",
    receipt: "wave.online rendered text 2026-09-03: 262 double-space runs across the home page HTML",
  },
  "string-whitespace": {
    severity: "error",
    summary: "no leading/trailing whitespace in a copy string (concatenation pieces and class lists are exempt)",
    receipt: "rendered ' Sign in' shifts the button glyph; trailing space breaks the <title>",
  },
  "em-dash-budget": {
    severity: "warn",
    summary: "em-dashes per file are budgeted (default max 1 — WORKER-CONTRACT copy rules); --strict-em-dash makes it an error",
    receipt: "wave.online 2026-09-03: 26 em-dashes on one page; docs.wave.online: 23",
  },
};

// ── Code-vs-copy classifier ──

/** A string that is code, not copy: URLs, paths, CSS, class lists, identifiers, hex, numbers. */
export function isCodeLike(s) {
  const t = s.trim();
  if (t.length < 2) return true;
  if (!/[A-Za-z]/.test(t)) return true;
  if (/^(https?:)?\/\//.test(t) || /^[\w.-]+\.(com|online|dev|io|md|json|ts|js|css|svg|png)\b/i.test(t)) return true;
  if (/^[\w@./:%-]+$/.test(t) && !/\s/.test(t) && /[/._:@-]/.test(t)) return true; // path / id / mime / key
  // CSS: property lists or rule blocks — but never prose that happens to carry ';' and ':'.
  if ((/^[.#@\w\s,>:\[\]="'()-]*\{[^}]*\}/.test(t) || /^\s*[\w-]+\s*:\s*[^;]+;/.test(t)) && !/[.!?]\s+[A-Z]/.test(t)) return true;
  if (/^[\w-]+(\s+[\w-]+)+$/.test(t) && /[-\[\]:]/.test(t) && !/[A-Z][a-z]/.test(t)) return true; // class list
  if (/^<[^>]+>$/.test(t)) return true; // a lone tag
  if (/^[A-Z0-9_]+$/.test(t)) return true; // CONSTANT
  if (/^[a-z]+([A-Z][a-z0-9]*)+$/.test(t)) return true; // camelCase identifier
  return false;
}

// ── Checks ──────────────────────────────────────────────────────────────────────────────────────

function wordsOf(text) {
  return text.trim().split(/\s+/).filter((w) => /[A-Za-z]/.test(w));
}

function stripPunct(w) {
  return w.replace(/^[^\w]+|[^\w]+$/g, "");
}

/** ALL-CAPS label: ≥2 alphabetic words, every alphabetic run uppercase, not all acronyms. */
function isShoutedLabel(text, labelContext) {
  if (/[/<>{}=\\|·]/.test(text)) return false;
  const words = wordsOf(text).map(stripPunct).filter((w) => /[A-Za-z]{2,}/.test(w));
  if (words.length < 2 || words.length > 8) return false;
  if (!words.every((w) => w === w.toUpperCase())) return false;
  if (words.every((w) => ACRONYMS.has(w))) return false;
  return labelContext || words.some((w) => CAPS_TELLS.has(w));
}

/** Title Case label: ≥2 words, every non-acronym word capitalised, and a tell-word among them. */
function isTitleCaseLabel(text) {
  const words = wordsOf(text).map(stripPunct).filter(Boolean);
  if (words.length < 2 || words.length > 8) return false;
  const nonAcr = words.filter((w) => !(w === w.toUpperCase() && ACRONYMS.has(w)) && !/^[a-z]?\d/.test(w));
  if (nonAcr.length < 2) return false;
  if (!nonAcr.every((w) => /^[A-Z]/.test(w))) return false;
  return nonAcr.slice(1).some((w) => TITLE_CASE_TELLS.has(w));
}

export function checkSegment(seg) {
  const findings = [];
  const { text } = seg;
  const push = (rule, index, sample) => findings.push({ rule, index, sample: sample.trim().slice(0, 90) });
  const proseLike = seg.kind === "cta" || seg.kind === "jsx" || seg.kind === "text" || !isCodeLike(text);
  if (!proseLike) return findings;

  let m;
  COUNT_NOUN_RE.lastIndex = 0;
  while ((m = COUNT_NOUN_RE.exec(text))) push("count-noun-agreement", seg.index + m.index, `${m[0]} → ${m[1]} of ${m[2]}s`);
  QUANT_NOUN_RE.lastIndex = 0;
  while ((m = QUANT_NOUN_RE.exec(text))) push("count-noun-agreement", seg.index + m.index, `${m[0]} → ${m[1]} ${m[2]}s`);

  const labelContext = seg.kind === "cta" || seg.kind === "jsx" || Boolean(seg.isLabel);
  if (seg.kind !== "text" && seg.kind !== "template") {
    if (isShoutedLabel(text, labelContext)) push("cta-caps", seg.index, `${text} → sentence case`);
    else if ((seg.kind === "cta" || seg.isLabel) && isTitleCaseLabel(text)) push("cta-caps", seg.index, `${text} → sentence case`);
  }

  if (/\s/.test(text.trim())) {
    // 'api' / 'Api' as a standalone term. Path segments (/api), hosts (api.wave.online) and
    // identifiers (apiKey) never split into a bare token, so they stay quiet.
    const tre = /(^|\s)(api|Api)(?=$|[\s,.;:!?)]|'s\b)(?![./:@-])/g;
    while (!seg.keywordKey && (m = tre.exec(text))) {
      const tail = text.slice(m.index + m[0].length, m.index + m[0].length + 3);
      if (/^\.[a-z]/i.test(tail) || /^\//.test(tail)) continue;
      push("api-term-case", seg.index + m.index + m[1].length, `${m[2]} → API`);
    }
    NOUN_AS_VERB_RE.lastIndex = 0;
    while ((m = NOUN_AS_VERB_RE.exec(text))) push("login-verb-noun", seg.index + m.index, `${m[0]} → verb is two words (log in / sign in / set up)`);
    VERB_AS_NOUN_RE.lastIndex = 0;
    while ((m = VERB_AS_NOUN_RE.exec(text))) push("login-verb-noun", seg.index + m.index, `${m[0]} → modifier is hyphenated (${m[1].replace(" ", "-")} ${m[2]})`);
    OXFORD_RE.lastIndex = 0;
    while ((m = OXFORD_RE.exec(text))) push("oxford-comma", seg.index + m.index, `${m[0]} → serial comma before and/or`);
    // Double spaces: prose strings only. Code samples (URLs, <placeholders>, shell prompts, braces)
    // and strings under code-ish keys align columns on purpose.
    const codeish = /:\/\/|[<>{}$`\\]/.test(text) || /^\s*[>$#]/.test(text) || Boolean(seg.codeKey);
    if ((seg.kind === "string" || seg.kind === "json" || seg.kind === "jsx") && !codeish) {
      const dre = /\S {2,}\S/g;
      while ((m = dre.exec(text))) push("double-space", seg.index + m.index, m[0]);
    }
  }

  const proseShaped = /^\s*[A-Z][^/{}<>=]*$/.test(text) && wordsOf(text).length >= 3 && !/\n/.test(text);
  if ((seg.kind === "string" || seg.kind === "json") && !seg.concat && !seg.attr && !seg.jsxExpr && proseShaped) {
    if (/^\s/.test(text) || (/\s$/.test(text) && !/\n\s*$/.test(text))) {
      push("string-whitespace", seg.index, JSON.stringify(text.slice(0, 40)));
    }
  }
  return findings;
}

