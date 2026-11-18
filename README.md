<!-- SPDX-License-Identifier: Apache-2.0 -->

# fsl-dafny

承認済みの [FSL](https://github.com/ymm-oss/fsl) 仕様から、TypeScript のコア（状態遷移の reducer）を生成します。コアの元になる Dafny モデルは、不変条件がどのサイズでも成り立つことを証明済みです。生成したコアは fslc と同じ遷移をするかどうかも機械で確かめてから出力します。

各部の保証、検証結果、ネガティブコントロールは [docs/details.md](docs/details.md)（英語）を参照してください。

## 必要なもの

- `fslc` 5.1.0（[release binary](https://github.com/ymm-oss/fsl/releases/tag/v5.1.0)）。`PATH` になければ、`FSLC=/path/to/fslc` で場所を渡す。
- `dafny` 4.11
- Node 22.18 以上と `npm ci`
- `--ai` を使う場合は `claude` CLI

## 仕様からコアを作る

FSL のファイルは書き換えず、そのパスを `core.mjs` に渡します。`core.mjs` は FSL から Dafny のモジュールを生成し、証明を検査してから、TS のコアを生成して仕様と突き合わせます。

例として、`spec Booking { ... }` と書かれた `booking.fsl` を使います。

1. FSL の仕様を用意します。
   - `fslc check booking.fsl` が `"result": "ok"` を返す仕様を使います。
   - ファイルはどこに置いても構いません。このリポジトリにコピーする必要もありません。
   - 出力の名前（以下の `<Name>`）は `spec` の名前（この例では `Booking`）で、`--name` で変えられます。

2. `--widen` に入れる型を選びます。
   - 仕様にある `type T = 0..hi` の型を1つずつ見て、範囲を本番の数に書き換えても仕様の決まりが変わらない型を選びます。新しく型を作るわけではありません。
   - `specs/seat_booking.fsl` の場合は次のとおりです。

     | 仕様の型 | 本番の数に書き換えると | `--widen` |
     |---|---|---|
     | `type SeatId = 0..2` | `0..499` にしても「空席だけ予約できる」「1人2席まで」は同じ | 入れる |
     | `type UserId = 0..1` | `0..99` にしても決まりは同じ | 入れる |
     | （例）`type Retry = 0..3` | `0..499` にすると「3回まで」が「500回まで」に変わる | 入れない |

   - 入れた型は、個数を引数に取るコアになります。証明はどの個数でも成り立ち、アプリは `init` と `step` を呼ぶたびに `{ SeatId: 500, UserId: 100 }` のような個数を渡します。
   - 入れなかった型は、仕様の範囲のままです。`SeatId` を入れ忘れると、コアは座席 0〜2 しか扱えず、座席 3 の予約は `null` で拒否されます。
   - 仕様で `symmetric` と宣言した型は、入れなくても対象になります。

3. FSL から Dafny のモジュールを生成します。証明をモデルに任せるときは、`core.mjs` が生成するのでこの手順は要りません。
   ```bash
   mkdir -p out
   fslc kernel path/to/booking.fsl > out/Booking.kernel.json
   node gen.mjs out/Booking.kernel.json --widen SeatId,UserId --name Booking > out/Booking.gen.dfy
   ```
   - `out/Booking.gen.dfy` には、状態、初期状態、各 action のガードと更新、証明すべき補題（本体なし）が入ります。

4. 証明を用意します。証明ファイルはこのリポジトリの `proofs/<Name>.proof.dfy` に置きます。
   - モデルに任せるときは、ファイルを置かずに `--ai` を付けて実行します。証明が通らなければ、モデルが最大3回書き直します。
   - 手で書くときは、次の形で書き、手順3で生成した `out/<Name>.gen.dfy` の本体のない補題を埋めます。
     ```dafny
     include "../out/Booking.gen.dfy"

     module BookingProof refines BookingSpec {
       lemma InitEstablishes(c: Config) { ... }
       lemma <action>_Preserves(...) { ... }
     }
     ```

5. 実行します。
   ```bash
   node core.mjs path/to/booking.fsl --widen SeatId,UserId --ai --out ../my-app/src/core
   ```
   - 終了コードが 0 のときだけ、`--out` に `Booking.ts`、`Booking.cjs`、`Booking.d.cts` が出力されます。
   - 1回の実行に 25〜55 秒ほどかかります。途中経過は表示されず、最後に JSON の結果を1行出力します。
   - 結果の `divergences` と `disagreements` が 0 なら、生成したコアと仕様が一致しています。
   - `--watch` を付けると、仕様または証明が変わるたびに再実行します。

6. アプリから使います。アプリ側には `bignumber.js` が必要です。
   ```ts
   import { init, step, type Sizes, type State } from "./core/Booking.ts";

   const sizes: Sizes = { SeatId: 500, UserId: 100 };
   let state: State = init(sizes);
   const next = step(sizes, state, { action: "book", params: { s: 10, u: 7 } });
   if (next) state = next; // null は仕様が許さない操作
   ```
   - `State` は plain JSON なので、そのまま保存できます。保存した状態を読み込んで渡すと、不変条件を検査し直します。検査を通らなければ `CoreInputError` を投げます。
   - `.ts` を直接 import する場合は、tsc に `allowImportingTsExtensions` が必要です。

動く例は `node core.mjs specs/seat_booking.fsl --widen SeatId,UserId` を実行してから、`node example/seat-booking.ts` で試せます。

## 失敗したとき

| 表示 | 意味 |
|---|---|
| `FAILED at fslc kernel` | fslc が仕様を受け付けていない。`fslc check` で確認する。 |
| `FAILED at fslc verify` | 仕様のサイズで不変条件などが破れる。表示された action の列が反例なので、仕様を直す。 |
| `unsupported: ...`（exit 2） | gen.mjs が翻訳できない構文を使っている。対応範囲は [docs/details.md](docs/details.md) にある。 |
| Dafny の `Error`（`FAILED at proof gates`） | 証明が足りないか、仕様のサイズより大きいときだけ破れるバグが仕様にある。 |
| `divergences` が 1 以上 | 生成したコアが仕様と違う遷移をした。fsl-dafny の不具合なので報告してほしい。 |

### 既知の問題

- 証明ファイルがない、または空のときのメッセージが分かりにくい。また、本体のない証明ファイルを置いたまま `--ai` を使うと、モデルを呼ばずに止まる（[#2](https://github.com/ymm-oss/fsl-dafny/issues/2)）。
- 上限を `0..N - 1` のような式で書くと、ランダム検査のサイズがずれる（[#3](https://github.com/ymm-oss/fsl-dafny/issues/3)）。

## License

Apache-2.0（`LICENSE`）
