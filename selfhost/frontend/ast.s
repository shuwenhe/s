package selfhost.frontend

use std.option.Option
use std.vec.Vec

pub struct UseDecl {
    path: String,
    alias: Option[String],
}

pub struct Field {
    name: String,
    type_name: String,
    is_public: bool,
}

pub struct Param {
    name: String,
    type_name: String,
}

pub struct FunctionSig {
    name: String,
    generics: Vec[String],
    params: Vec[Param],
    return_type: Option[String],
}

pub struct NamePattern {
    name: String,
}

pub struct WildcardPattern {}

pub struct VariantPattern {
    path: String,
    args: Vec[Pattern],
}

pub enum Pattern {
    Name(NamePattern),
    Wildcard(WildcardPattern),
    Variant(VariantPattern),
}

pub struct IntExpr {
    value: String,
    inferred_type: Option[String],
}

pub struct StringExpr {
    value: String,
    inferred_type: Option[String],
}

pub struct BoolExpr {
    value: bool,
    inferred_type: Option[String],
}

pub struct NameExpr {
    name: String,
    inferred_type: Option[String],
}

pub struct BorrowExpr {
    target: Box[Expr],
    mutable: bool,
    inferred_type: Option[String],
}

pub struct BinaryExpr {
    left: Box[Expr],
    op: String,
    right: Box[Expr],
    inferred_type: Option[String],
}

pub struct MemberExpr {
    target: Box[Expr],
    member: String,
    inferred_type: Option[String],
}

pub struct IndexExpr {
    target: Box[Expr],
    index: Box[Expr],
    inferred_type: Option[String],
}

pub struct CallExpr {
    callee: Box[Expr],
    args: Vec[Expr],
    inferred_type: Option[String],
}

pub struct MatchArm {
    pattern: Pattern,
    expr: Expr,
}

pub struct MatchExpr {
    subject: Box[Expr],
    arms: Vec[MatchArm],
    inferred_type: Option[String],
}

pub struct IfExpr {
    condition: Box[Expr],
    then_branch: BlockExpr,
    else_branch: Option[Box[Expr]],
    inferred_type: Option[String],
}

pub struct WhileExpr {
    condition: Box[Expr],
    body: BlockExpr,
    inferred_type: Option[String],
}

pub struct ForExpr {
    name: String,
    iterable: Box[Expr],
    body: BlockExpr,
    inferred_type: Option[String],
}

pub struct BlockExpr {
    statements: Vec[Stmt],
    final_expr: Option[Expr],
    inferred_type: Option[String],
}

pub enum Expr {
    Int(IntExpr),
    String(StringExpr),
    Bool(BoolExpr),
    Name(NameExpr),
    Borrow(BorrowExpr),
    Binary(BinaryExpr),
    Member(MemberExpr),
    Index(IndexExpr),
    Call(CallExpr),
    Match(MatchExpr),
    If(IfExpr),
    While(WhileExpr),
    For(ForExpr),
    Block(BlockExpr),
}

pub struct LetStmt {
    name: String,
    type_name: Option[String],
    value: Expr,
}

pub struct ReturnStmt {
    value: Option[Expr],
}

pub struct ExprStmt {
    expr: Expr,
}

pub enum Stmt {
    Let(LetStmt),
    Return(ReturnStmt),
    Expr(ExprStmt),
}

pub struct FunctionDecl {
    sig: FunctionSig,
    body: Option[BlockExpr],
    is_public: bool,
}

pub struct StructDecl {
    name: String,
    generics: Vec[String],
    fields: Vec[Field],
    is_public: bool,
}

pub struct EnumVariant {
    name: String,
    payload: Option[String],
}

pub struct EnumDecl {
    name: String,
    generics: Vec[String],
    variants: Vec[EnumVariant],
    is_public: bool,
}

pub struct TraitDecl {
    name: String,
    generics: Vec[String],
    methods: Vec[FunctionSig],
    is_public: bool,
}

pub struct ImplDecl {
    target: String,
    trait_name: Option[String],
    generics: Vec[String],
    methods: Vec[FunctionDecl],
}

pub enum Item {
    Function(FunctionDecl),
    Struct(StructDecl),
    Enum(EnumDecl),
    Trait(TraitDecl),
    Impl(ImplDecl),
}

pub struct SourceFile {
    package: String,
    uses: Vec[UseDecl],
    items: Vec[Item],
}
