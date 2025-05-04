I eventually discovered that nothing mystical was wrong with my SVG builder—it was simply running head‑first into Polkadot’s much tighter EVM limits. On Westend Asset Hub the EVM pallet is wrapped in Substrate’s “weight v2” metering: every opcode, memory grow, storage read/write and proof‑of‑validity (PoV) byte counts against a per‑block PoV limit (≈5 MiB) which is then converted into an effective gas cap (≈15 M gas) via the pallet’s weight_to_gas mapping. Once my 41×82 dynamic string concatenations plus the in‑EVM Base64 push the PoV or weight budget over that threshold, the WASM host simply traps with no revert string.

By contrast, on Sepolia the block gas limit today sits at roughly 36 million gas, and Geth’s default RPC gas cap (--rpc.gascap) is essentially 2⁶³—so my single‑shot SVG loop fit comfortably under Sepolia’s ceilings and completed before Geth’s 5 s execution timeout.

Knowing that, I re‑architected the on‑chain renderer: instead of doing 41 string‑concats per row in one giant string.concat, I pre‑built each row into a fixed‑size bytes buffer (which EVM memory grows only linearly, not quadratically) and condensed the grid to 10×10. That change cut both the gas and WASM memory footprints enough to stay under Westend’s PoV/weight and 4 GiB WASM limits—and now my eth_call view returns the full Base64 SVG without panicking .



