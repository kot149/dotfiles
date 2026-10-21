/**
 * Flag Claude-flavored Japanese phrasing: vague verbs, test red/green metaphors,
 * English "pin" used as a Japanese verb, and parenthetical notes tacked onto a heading.
 *
 * Matching is done on the part of speech and the dictionary form of each token,
 * so every conjugation is covered and same-kanji nouns (採用, 転倒) are not.
 */
import { tokenize } from "kuromojin@3.0.1";

// 「効く」「壊れる」の係り元がこれらの抽象的な語のときだけ、比喩として指摘する。
const VAGUE_SUBJECTS = new Set([
  "判断",
  "意思決定",
  "決定",
  "設計",
  "仕様",
  "議論",
  "説明",
  "理解",
  "見通し",
  "レビュー",
  "品質",
  "検討",
  "評価",
  "分析",
  "前提",
  "整合性",
  "一貫性",
  "意味",
  "体験",
  "信頼",
  "モデル",
  "構造",
  "世界観",
  "論理",
  "バランス",
  "方針",
  "抽象",
  "ここ",
  "そこ",
  "点",
  "方向",
]);
const FINANCIAL_FAILURE = new Set(["経営", "財政", "家計", "ローン", "国家", "生活", "資金", "事業"]);
const LANDING_PLACES = new Set(["両足", "足", "滑走路", "地面", "床", "マット", "ジャンプ", "空中"]);
const CONTESTS = new Set(["試合", "勝負", "対戦", "決勝", "ゲーム", "選挙", "裁判", "訴訟"]);
// 「払う」の目的語として正しい語。金額やコストのほか、「注意を払う」などの慣用句と「埃を払う」。
const PAYABLE =
  /(?:コスト|費用|代償|対価|犠牲|ツケ|ペナルティ|オーバーヘッド|注意|敬意|関心|努力|税|金|代|料|費|円|ドル|埃|ほこり|塵|雪)$/i;

const CANON_ADVICE =
  "「正本」「正典」→ 何を基準にするのかを具体的に書く" +
  " (例: 「どこが正本か読めない」→「同じ結論が3か所にあり、どれを直せばよいか決まらない」)";

const INSUFFICIENT_ADVICE =
  "「〜では足りない」→ 何が欠けていて何が起きるのかを具体的に書く" +
  " (例: 「単体テストだけでは足りない」→「単体テストだけではDB接続の失敗を検出できない」)";

/**
 * 「〜では足りない」「〜じゃ足りない」の形。「お金が足りない」のように不足するものを
 * 名指しする形と「取るに足らない」は対象外。
 */
const isInsufficient = (tokens, i) => {
  const before = neighbor(tokens, i, -1).surface_form;
  const after = dictionaryForm(neighbor(tokens, i, 1));
  return ["は", "じゃ"].includes(before) && ["ない", "ぬ", "ます"].includes(after);
};

const VERB_RULES = {
  寄せる: {
    advice:
      "「寄せる」→ 何をどの形に合わせるのかを具体的に書く" +
      " (例: 「公開語彙に寄せる」→「公開語彙と同じ invalid_date_value を使う」)",
  },
  倒す: {
    advice:
      "「〜に倒す」→ どちらの値や挙動を選ぶのかを具体的に書く" +
      " (例: 「安全側に倒す」→「判定材料が取れないときは拒否する」)",
  },
  採る: {
    advice: "「採る」→「採用する」と書く (例: 「この方式を採る」→「この方式を採用する」)",
    // Only the dictionary form is safe to rewrite mechanically; 採った などは指摘だけ。
    fix: { 採る: "採用する" },
  },
  申し送る: {
    // No fixer: 引き継ぎの意味なら書き換えてはいけないので、置換先は文脈で決まる。
    advice: "「申し送り」→「見送り」と書く (例: 「今回は申し送りとする」→「今回は見送る」)",
  },
  化ける: {
    advice:
      "「化ける」→ 何がどう変わるのかを具体的に書く" +
      " (例: 「巨大なPRに化ける」→「PRの差分が数千行に膨らむ」)",
  },
  通す: {
    // 「目を通す」「筋を通す」は慣用句なので対象外。
    skip: (tokens, i) => ["目", "筋"].includes(dictionaryForm(tokens[i - 2] ?? {})),
    advice:
      "「〜を通す」→ 何をどう扱う / 維持するのかを具体的に書く" +
      " (例: 「db側のゲートもこの関数を通す」→「db側のゲートもこの関数を経由させる」" +
      " /「この方針で通す」→「新規ファイルでも同じ命名規則を使う」)",
  },
  壊れる: {
    // 「ファイルが壊れる」「HDDが壊れる」は字義どおりなので、抽象的な係り元と、
    // 対象を名指ししない「壊れるもの」「壊れるのは」の形だけを拾う。
    skip: (tokens, i) => !hasVagueSubject(tokens, i) && !isNominalized(tokens, i),
    advice:
      "「壊れる」→ 何がどうなるのかを具体的に書く" +
      " (例: 「放置した場合に壊れるもの」→「放置した場合に起きること」)",
  },
  払う: {
    // 目的語が書かれていない「先に払う」は判断できないので対象外。
    skip: (tokens, i) => {
      const object = objectNoun(tokens, i);
      return !object || PAYABLE.test(object);
    },
    advice:
      "「払う」→ 金額やコスト以外には使わず、実際の動作を書く" +
      " (例: 「毎回次の処理を払っている」→「毎回次の処理を実行している」" +
      " /「コールドスタートを払う行が増える」→「コールドスタートになる行が増える」)",
  },
  効く: {
    // 「キャッシュが効く」「薬が効く」は作用が具体的に決まっているので対象外。
    skip: (tokens, i) => !hasVagueSubject(tokens, i),
    advice:
      "「効く」→ 何にどう作用するのかを具体的に書く" +
      " (例: 「着手順を決めるならここが効く」→「着手順を決めるならこの点を先に見る」)",
  },
  要る: {
    // 平仮名の「いる」(居る) は対象外。
    skip: (tokens, i) => !tokens[i].surface_form.startsWith("要"),
    advice:
      "「要る」→「必要」と書く" +
      " (例: 「force pushが要ります」→「force pushが必要です」/「再依頼は要りません」→「再依頼は必要ありません」)",
    fix: (tokens, i) => fixNeeded(tokens, i),
  },
  足す: {
    // 「用を足す」は慣用句、「足し合わせる」のような複合動詞は計算の意味なので対象外。
    skip: (tokens, i) => objectNoun(tokens, i) === "用" || neighbor(tokens, i, 1).pos === "動詞",
    advice: "「足す」→「追加する」と書く (例: 「テストを足す」→「テストを追加する」)",
    // 足さない、足せば などは語尾の組み替えが必要なので指摘だけ。
    fix: { 足す: "追加する", 足し: "追加し" },
  },
  足りる: {
    skip: (tokens, i) => !isInsufficient(tokens, i),
    advice: INSUFFICIENT_ADVICE,
  },
  足る: {
    skip: (tokens, i) => !isInsufficient(tokens, i),
    advice: INSUFFICIENT_ADVICE,
  },
};

/**
 * 「要る」の活用形を「必要」に書き換える置換。後ろの助動詞ごと置き換える形は fixEnd を返す。
 * 「要った」のように言い換えが一つに決まらない形は undefined で、指摘だけにする。
 */
const fixNeeded = (tokens, i) => {
  const surface = tokens[i].surface_form;
  const j = neighborIndex(tokens, i, 1);
  const next = tokens[j] ?? {};
  const nextForm = dictionaryForm(next);
  const through = (replacement) => ({ replacement, fixEnd: next.word_position - 1 + next.surface_form.length });
  if (surface === "要る") {
    // 「要るリクエスト」「要るのは」「要るので」は連体形なので「必要な」にする。
    return { replacement: next.pos === "名詞" || nextForm === "ので" ? "必要な" : "必要" };
  }
  if (surface === "要ら") return nextForm === "ない" ? { replacement: "必要" } : undefined;
  if (surface !== "要り") return undefined;
  if (next.pos_detail_1 === "読点") return { replacement: "必要で" };
  if (nextForm !== "ます") return undefined;
  if (next.surface_form === "ます") return through("必要です");
  if (next.surface_form === "ませ") return through("必要ありませ");
  if (next.surface_form === "まし") return through("必要でし");
  return undefined;
};

const NOUN_RULES = {
  破綻: {
    // 「経営破綻」「財政破綻」は確立した用語。
    skip: (tokens, i) => precedingNouns(tokens, i, 2).some((n) => FINANCIAL_FAILURE.has(n)),
    advice:
      "「破綻」→ 何がどうなるのかを具体的に書く" +
      " (例: 「3つ目の消費者が出た時点で破綻する」→「3つ目の消費者が出た時点で同じ定数を2か所で直すことになる」)",
  },
  着地: {
    // 体操や着陸の「着地」は字義どおりの動作。
    skip: (tokens, i) => precedingNouns(tokens, i, 3).some((n) => LANDING_PLACES.has(n)),
    advice:
      "「着地」→「完了」「マージ」など実際の状態を書く" +
      " (例: 「このチケットが着地すると」→「このチケットがマージされると」)",
  },
  決着: {
    // 試合や勝負の「決着」は字義どおり。
    skip: (tokens, i) => precedingNouns(tokens, i, 4).some((n) => CONTESTS.has(n)),
    advice:
      "「決着」→ 何がどう決まったのかを具体的に書く" +
      " (例: 「既存レビューで決着済み」→「既存レビューで対応不要と決まっている」)",
  },
  整理: {
    // 「整理する」や片付けの意味ではなく、認識そのものを指す「という整理」「この整理」だけを拾う。
    skip: (tokens, i) => {
      const before = neighbor(tokens, i, -1);
      const after = dictionaryForm(neighbor(tokens, i, 1));
      if (["だ", "です"].includes(after)) return false;
      const framed = dictionaryForm(before) === "という" || before.pos === "連体詞";
      // 「この整理を進める」のように動作の対象になっている形は片付けの意味。
      return !framed || ["を", "が"].includes(after);
    },
    advice:
      "「〜という整理です」→ 認識の中身をそのまま言い切る" +
      " (例: 「このガードは保険という整理です」→「このガードは保険です」)",
  },
  正本: { advice: CANON_ADVICE },
  帰結: {
    // 「〜に帰結する」という動詞用法は対象外で、「〜の帰結」「この帰結」「必然的帰結」を拾う。
    skip: (tokens, i) => dictionaryForm(neighbor(tokens, i, 1)) === "する",
    advice:
      "「帰結」→ 何が原因で何が起きるのかを書く" +
      " (例: 「ヘッダ削除の帰結」→「ヘッダを削除したので、409は行内のerrorにだけ残る」)",
  },
};

// 五段動詞の可能形は kuromoji が別の基本形を立てる (採れる, 倒せる) ため、辞書引きの前に
// 元の動詞へ戻す。一段動詞の可能形は「られる」が別トークンになるので、ここには要らない。
const POTENTIAL_FORMS = {
  採れる: "採る",
  倒せる: "倒す",
  通せる: "通す",
  申し送れる: "申し送る",
  払える: "払う",
  足せる: "足す",
};

// テストの成否の比喩でしか使わない語。単独で出ても指摘する。大文字小文字は問わない。
const COLOR_METAPHORS = new Set(["グリーン", "レッド", "green", "red"]);
// 色そのものも指す語。テストの文脈があるときだけ指摘する。
const COLOR_BASES = new Set(["緑", "赤", "赤い", "真っ赤"]);
const COLOR_TAILS = new Set([
  "なる",
  "まま",
  "返す",
  "保つ",
  "維持",
  "戻す",
  "戻る",
  "キープ",
  "状態",
]);
const COLOR_SUBJECTS = new Set([
  "テスト",
  "test",
  "ci",
  "ビルド",
  "build",
  "lint",
  "チェック",
  "check",
  "スイート",
  "suite",
  "ジョブ",
  "job",
  "パイプライン",
  "pipeline",
]);
const LATIN_WORD = /^[A-Za-z][A-Za-z0-9_-]*$/;
// Allows one intervening particle between the colour and the predicate.
const COLOR_WINDOW = 2;
// 「全テストが緑」のように主語との間に接頭詞や助詞が挟まる分の余裕。
const COLOR_SUBJECT_WINDOW = 4;
const COLOR_ADVICE =
  "テストの赤/緑 → 「テストが通る/成功する/pass」「テストが落ちる/失敗する/fail」と書く" +
  " (例: 「全テストが緑のまま」→「全テストが通ったままで、退行を検出できない」)";

const LEANING_ADVICE =
  "「〜寄り」→ どちらに近いかではなく、実際の判断を言い切る" +
  " (例: 「「直さなくてよい」寄りです」→「今回は直さなくてよい」)";

// 「静かに」「黙って」が人の動作を表す本来の意味で係る動詞。これらだけ対象外にする。
const QUIET_LITERAL = new Set([
  "話す",
  "言う",
  "聞く",
  "聴く",
  "待つ",
  "見る",
  "読む",
  "座る",
  "立つ",
  "歩く",
  "眠る",
  "寝る",
  "笑う",
  "頷く",
  "うなずく",
  "過ごす",
  "過ぎる",
  "暮らす",
  "食べる",
  "する",
  "従う",
  "受け取る",
  "見送る",
  "立ち去る",
  "去る",
  "帰る",
  "引き下がる",
  "祈る",
  "考える",
]);
const QUIET_ADVICE =
  "「静かに〜する」「黙って〜する」→ 何がどう起きるのかを具体的に書く" +
  " (例: 「宣言外プロパティが黙って捨てられる」→「宣言外プロパティは検証で落ちず、応答から抜ける」)";

// 「正典」だけは 正 (接頭詞) + 典 に分かれるので、トークンではなく文字列で拾う。
const CANON_WORDS = /正典/g;

const PIN_ADVICE =
  "「pinする/される」→「固定する/される」と書く" +
  " (例: 「テストが仕様をpinする」→「テストが仕様を固定し、変わったら落ちるようにする」)";

// A label dropped in front of a paragraph, plain or bold:
// 「結論: ...」「**結論**: ...」「**結論:** ...」「結論：...」
const LEAD_LABELS = ["結論", "要点", "まとめ", "ポイント", "補足", "概要", "TL;DR"];
const LEAD_LABEL = new RegExp(
  String.raw`^(?:\*\*)?(?:${LEAD_LABELS.join("|")})(?:\*\*)?[ \t]*[:：](?:\*\*)?[ \t]*(?=\S)`,
);
const LEAD_LABEL_ADVICE =
  "行頭の「結論:」のようなラベル → ラベルを外して本文をそのまま書くか、文に溶かす" +
  " (例: 「結論: この方式を採用する」→「この方式を採用する」/「結論としては、この方式を採用する」)";

// 見出しに付けた括弧の補足。空の () は補足ではないので対象外で、丸括弧は半角と全角の両方を見る。
const HEADING_PARENTHETICAL = /[(（][^)）\n]*[^\s()（）][^)）\n]*[)）]/g;
const HEADING_PARENTHETICAL_ADVICE =
  "見出しの補足 () → 括弧を外して見出しを短くし、補足は本文に書く" +
  " (例: 「## 適用 (chezmoi apply が必要)」→「## 適用」と、本文に適用手順を書く)";

const URL = /\b(?:https?|git|ssh):\/\/\S+/g;

/** 直前 span トークンに現れる名詞の基本形。係り元の判定に使う。 */
const precedingNouns = (tokens, i, span) =>
  tokens
    .slice(Math.max(0, i - span), i)
    .filter((token) => token.pos === "名詞")
    .map((token) => dictionaryForm(token));

/** 「〜が効く」「〜が壊れる」の係り元が、具体的に書き直すべき抽象語かどうか。 */
const hasVagueSubject = (tokens, i) =>
  precedingNouns(tokens, i, 4).some((noun) => VAGUE_SUBJECTS.has(noun));

/** 「壊れるもの」「壊れるのは」のように、形式名詞を受けて対象を名指ししない形。 */
const isNominalized = (tokens, i) => {
  const after = neighbor(tokens, i, 1);
  return after.pos === "名詞" && after.pos_detail_1 === "非自立";
};

/** 「〜を払う」の目的語の複合名詞。「を」「は」「も」で受けていなければ空文字。 */
const objectNoun = (tokens, i) => {
  const particle = neighborIndex(tokens, i, -1);
  if (particle < 0 || tokens[particle].pos !== "助詞") return "";
  if (!["を", "は", "も"].includes(tokens[particle].surface_form)) return "";
  let noun = "";
  for (let j = neighborIndex(tokens, particle, -1); j >= 0 && tokens[j].pos === "名詞"; j = neighborIndex(tokens, j, -1)) {
    noun = tokens[j].surface_form + noun;
  }
  return noun;
};

const dictionaryForm = (token) =>
  token.basic_form && token.basic_form !== "*" ? token.basic_form : token.surface_form;

/** Blank out URLs while keeping every other character at its original offset. */
const maskUrls = (text) => text.replace(URL, (m) => " ".repeat(m.length));

/** The nearest token in the given direction, skipping the whitespace kuromoji emits as 記号. */
const neighborIndex = (tokens, i, step) => {
  for (let j = i + step; j >= 0 && j < tokens.length; j += step) {
    if (tokens[j].surface_form.trim()) return j;
  }
  return -1;
};

const neighbor = (tokens, i, step) => tokens[neighborIndex(tokens, i, step)] ?? {};

const isAttributive = (tokens, i) => dictionaryForm(neighbor(tokens, i, 1)) === "の";

/** 「Red Hat」「green thread」のように英単語と連なる形。色の比喩ではなく固有名詞や術語。 */
const isLatinCompound = (tokens, i) =>
  [-1, 1].some((step) => LATIN_WORD.test(neighbor(tokens, i, step).surface_form ?? ""));

/**
 * テストの成否を色で言い換えた表現。「グリーン」「レッド」は単独でも拾い、
 * 「緑」「赤」は前にテストの主語があるか後ろに状態の述語が続くときだけ拾う。
 */
const isTestColor = (tokens, i) => {
  const token = tokens[i];
  if (token.pos !== "名詞" && token.pos !== "形容詞") return false;
  const form = dictionaryForm(token);
  const isMetaphor = COLOR_METAPHORS.has(form.toLowerCase());
  if (!isMetaphor && !COLOR_BASES.has(form)) return false;
  // 「グリーンのアイコン」「Red Hat」のような色そのもの / 固有名詞の用法を外すため、
  // 連体修飾と英単語の複合語だけは文脈を見る。
  if (isMetaphor && !isAttributive(tokens, i) && !isLatinCompound(tokens, i)) return true;
  const before = tokens.slice(Math.max(0, i - COLOR_SUBJECT_WINDOW), i);
  const after = tokens.slice(i + 1, i + 1 + COLOR_WINDOW);
  return (
    before.some((t) => COLOR_SUBJECTS.has(dictionaryForm(t).toLowerCase())) ||
    after.some((t) => COLOR_TAILS.has(dictionaryForm(t)))
  );
};

/** 「〜寄り」が付く先の語。閉じ括弧が挟まるときは括弧の中の末尾の語を見る。 */
const leaningBase = (tokens, i) => {
  const j = neighborIndex(tokens, i, -1);
  if (j < 0) return {};
  return tokens[j].pos_detail_1 === "括弧閉" ? neighbor(tokens, j, -1) : tokens[j];
};

/**
 * 名詞以外に付く「寄り」。「安全寄り」「「見送り」寄り」のような名詞に付く形は
 * 語として定着しているので対象外で、用言や文を受ける形だけを指摘する。
 * 「歩み寄り」「左寄り」「寄り道」は一語にまとまるので surface が一致しない。
 */
const isLeaning = (tokens, i) => {
  if (tokens[i].pos !== "名詞" || tokens[i].surface_form !== "寄り") return false;
  const base = leaningBase(tokens, i);
  return Boolean(base.pos) && base.pos !== "名詞";
};

/** 「静かに」「黙って」の形。それぞれ 静か + に、黙っ + て に分かれる。 */
const isQuietAdverb = (tokens, i) => {
  const form = dictionaryForm(tokens[i]);
  const next = dictionaryForm(neighbor(tokens, i, 1));
  if (tokens[i].pos === "名詞" && form === "静か") return next === "に";
  if (tokens[i].pos === "動詞" && form === "黙る") return next === "て";
  return false;
};

/**
 * 「静かに」「黙って」が係る用言の基本形。名詞 + する は名詞側を返す。
 * 目的語や読点を挟む形も拾えるよう、同じ文の中を前から探して最初の一つだけを見る。
 */
const quietTarget = (tokens, i) => {
  const particle = neighborIndex(tokens, i, 1);
  if (particle < 0) return "";
  for (let j = particle + 1; j < tokens.length; j += 1) {
    const token = tokens[j];
    if (token.pos_detail_1 === "句点") return "";
    // 補助動詞 (「〜ている」の いる) は係り先ではないので自立語だけを見る。
    if (token.pos === "動詞" && token.pos_detail_1 === "自立") return dictionaryForm(token);
    if (token.pos === "名詞" && dictionaryForm(neighbor(tokens, j, 1)) === "する") {
      return dictionaryForm(token);
    }
  }
  return "";
};

/** 指摘する「静かに」「黙って」の終端。該当しなければ -1。 */
const quietEnd = (tokens, i) => {
  if (!isQuietAdverb(tokens, i)) return -1;
  const target = quietTarget(tokens, i);
  if (!target || QUIET_LITERAL.has(target)) return -1;
  const particle = tokens[neighborIndex(tokens, i, 1)];
  return particle.word_position - 1 + particle.surface_form.length;
};

/** 動詞化した pin の動詞トークンの位置。「pin する」のように空白が挟まる形も拾う。 */
const pinVerbIndex = (tokens, i) => {
  const j = neighborIndex(tokens, i, 1);
  if (j < 0) return -1;
  const verb = dictionaryForm(tokens[j]);
  const surface = tokens[i].surface_form;
  if (surface.toLowerCase() === "pin") return verb === "する" ? j : -1;
  if (surface === "ピン") return ["留める", "止める"].includes(verb) ? j : -1;
  return -1;
};

/** Yield { index, length, advice, replacement } for every token that trips a rule. */
function* findMatches(tokens) {
  for (const [i, token] of tokens.entries()) {
    const dictionary = dictionaryForm(token);
    const form = POTENTIAL_FORMS[dictionary] ?? dictionary;
    const surface = token.surface_form;
    const hit = { index: token.word_position - 1, length: surface.length };
    const quiet = quietEnd(tokens, i);

    // 辞書にない漢語 (採番) は 採 (体言接続特殊２) + 番 に分かれるので、語幹だけの動詞は除く。
    if (token.pos === "動詞" && token.conjugated_form !== "体言接続特殊２" && VERB_RULES[form]) {
      const rule = VERB_RULES[form];
      if (rule.skip?.(tokens, i)) continue;
      const fix = typeof rule.fix === "function" ? rule.fix(tokens, i) : { replacement: rule.fix?.[surface] };
      yield { ...hit, advice: rule.advice, ...fix };
    } else if (token.pos === "名詞" && NOUN_RULES[form] && !NOUN_RULES[form].skip?.(tokens, i)) {
      yield { ...hit, advice: NOUN_RULES[form].advice };
    } else if (quiet >= 0) {
      yield { ...hit, length: quiet - hit.index, advice: QUIET_ADVICE };
    } else if (isLeaning(tokens, i)) {
      yield { ...hit, advice: LEANING_ADVICE };
    } else if (isTestColor(tokens, i)) {
      yield { ...hit, advice: COLOR_ADVICE };
    } else {
      const j = pinVerbIndex(tokens, i);
      if (j < 0) continue;
      // 「pin する」の空白ごと「固定する」に寄せるため、書き換えは動詞の直前まで含める。
      const isLatin = surface.toLowerCase() === "pin";
      yield {
        ...hit,
        advice: PIN_ADVICE,
        replacement: isLatin ? "固定" : undefined,
        fixEnd: tokens[j].word_position - 1,
      };
    }
  }
}

/** 形態素解析を経由せず、表記そのもので拾う語。 */
function* findTextMatches(text) {
  for (const match of text.matchAll(CANON_WORDS)) {
    yield { index: match.index, length: match[0].length, advice: CANON_ADVICE };
  }
}

function linter(context) {
  const { Syntax, RuleError, report, getSource, fixer, locator } = context;

  /** Report on the raw paragraph source, where the bold markers are still visible. */
  const checkLeadLabel = (node) => {
    const [label] = getSource(node).match(LEAD_LABEL) ?? [];
    if (!label) return;
    const range = [0, label.length];
    report(
      node,
      new RuleError(LEAD_LABEL_ADVICE, {
        padding: locator.range(range),
        fix: fixer.replaceTextRange(range, ""),
      }),
    );
  };

  /** Only the Str children are inspected, so a code span such as `useState()` is left alone. */
  const checkHeading = (node) => {
    for (const child of node.children ?? []) {
      if (child.type !== Syntax.Str) continue;
      for (const match of getSource(child).matchAll(HEADING_PARENTHETICAL)) {
        const range = [match.index, match.index + match[0].length];
        const options = { padding: locator.range(range) };
        report(child, new RuleError(HEADING_PARENTHETICAL_ADVICE, options));
      }
    }
  };

  return {
    // A list item holds its own Paragraph, so this covers bulleted labels too.
    [Syntax.Paragraph]: checkLeadLabel,
    [Syntax.Header]: checkHeading,
    async [Syntax.Str](node) {
      const text = maskUrls(getSource(node));
      const tokens = await tokenize(text);
      const matches = [...findMatches(tokens), ...findTextMatches(text)];
      for (const { index, length, advice, replacement, fixEnd } of matches) {
        const range = [index, index + length];
        // padding over index so the reported range covers the whole match.
        const options = { padding: locator.range(range) };
        if (replacement !== undefined) {
          options.fix = fixer.replaceTextRange([index, fixEnd ?? range[1]], replacement);
        }
        report(node, new RuleError(advice, options));
      }
    },
  };
}

export default { linter, fixer: linter };
