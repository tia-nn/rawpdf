package rawpdf.cst.syntax;

abstract TokenFlags(Int) {
	public static inline final NONE:TokenFlags = cast 0;
	public static inline final UNTERMINATED:TokenFlags = cast 1 << 0;
	public static inline final MISSING:TokenFlags = cast 1 << 1;

	/** フラグの和集合を返す **/
	@:op(A | B)
	public inline function or(a:TokenFlags):TokenFlags {
		return cast(this | cast a);
	}

	/** `a` のフラグをすべて含むかを判定する。 `NONE` を渡すと常に `true` になる。 **/
	public function has(a:TokenFlags) {
		final aa:Int = cast a;
		return (this & aa) == aa;
	}

	/** フラグが `NONE` かを判定する。 **/
	public inline function isNone() {
		return abstract == TokenFlags.NONE;
	}
}
