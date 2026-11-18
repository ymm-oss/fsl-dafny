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

例として、`spec Booking { ... }` と書かれた `booking.fsl` を使います。仕様ファイルはどこに置いても構いません。

1. 大きくしたい型を決めます。
   - ID のように、本番では仕様より大きなサイズで使う型を `--widen` に並べます。仕様で `symmetric` と宣言した型は指定しなくても対象になります。
   - 対象にできるのは `type T = 0..hi` の形の型だけです。

2. 証明を用意します。証明ファイルはこのリポジトリの `proofs/<Name>.proof.dfy` に置きます。`<Name>` は `spec` の名前で、`--name` で変えられます。
   - モデルに任せるときは、ファイルを置かずに `--ai` を付けて実行します。証明が通らなければ、モデルが最大3回書き直します。
   - 手で書くときは、次の形で書き、補題の本体を埋めます。どの補題に本体が必要かは、生成された `out/<Name>.gen.dfy` で確認します。
     ```dafny
     include "../out/Booking.gen.dfy"

     module BookingProof refines BookingSpec {
       lemma InitEstablishes(c: Config) { ... }
       lemma <action>_Preserves(...) { ... }
     }
     ```

3. 実行します。
   ```bash
   node core.mjs path/to/booking.fsl --widen SeatId,UserId --ai --out ../my-app/src/core
   ```
   - 終了コードが 0 のときだけ、`--out` に `Booking.ts`、`Booking.cjs`、`Booking.d.cts` が出力されます。
   - 1回の実行に 25〜55 秒ほどかかります。途中経過は表示されず、最後に JSON の結果を1行出力します。
   - 結果の `divergences` と `disagreements` が 0 なら、生成したコアと仕様が一致しています。
   - `--watch` を付けると、仕様または証明が変わるたびに再実行します。

4. アプリから使います。アプリ側には `bignumber.js` が必要です。
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
| `unsupported: ...`（exit 2） | gen.mjs が翻訳できない構文を使っている。対応範囲は [docs/details.md](docs/details.md) にある。 |
| Dafny の `Error`（`FAILED at proof gates`） | 証明が足りないか、仕様にバグがある。まず `fslc verify <spec>` で反例が出ないか確認する。 |
| `divergences` が 1 以上 | 生成したコアが仕様と違う遷移をした。fsl-dafny の不具合なので報告してほしい。 |

### 既知の問題

- 仕様のバグが反例ではなく Dafny のエラーとして返る（[#1](https://github.com/ymm-oss/fsl-dafny/issues/1)）。
- 証明ファイルがない、または空のときのメッセージが分かりにくい。また、本体のない証明ファイルを置いたまま `--ai` を使うと、モデルを呼ばずに止まる（[#2](https://github.com/ymm-oss/fsl-dafny/issues/2)）。
- 上限を `0..N - 1` のような式で書くと、ランダム検査のサイズがずれる（[#3](https://github.com/ymm-oss/fsl-dafny/issues/3)）。

## License

Apache-2.0（`LICENSE`）
