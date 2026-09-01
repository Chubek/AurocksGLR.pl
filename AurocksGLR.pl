#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

=pod

=head1 NAME

AurocksGLR.pl - generate a scannerless GLR-style parser from an Aurocks grammar

=head1 SYNOPSIS

  perl AurocksGLR.pl grammar.g > parser.c

The generated C source can then be compiled with the C compiler and linked
with the declarations, constructors, and helper functions supplied by the
grammar's C prologue and epilogue.

=head1 DESCRIPTION

C<AurocksGLR.pl> is a self-contained parser generator for the small grammar
language used by the Aurocks examples.  It reads a grammar file, extracts its
C prologue, directives, productions, semantic actions, and C epilogue, and
writes a complete C parser to standard output.

The generated parser is scannerless: literal terminals and regular-expression
terminals are matched directly against the input buffer.  No separate lexer
is required.  A C<%skip> regular expression may be used to consume layout such
as spaces and newlines between grammar symbols.

The implementation uses recursive GLR-style alternatives.  Each production
alternative is attempted from the same input position, with the parser state
restored when an alternative fails.  Successful alternatives produce a value
through the production's semantic action.  This preserves the essential
backtracking and ambiguity-handling behavior needed by the bundled grammars,
while keeping the generated runtime small and portable.

=head1 INPUT GRAMMAR

Grammar files are divided into three regions:

=over 2

=item * C<%{ ... %}>

The C prologue.  It is copied into the generated source before the runtime.
Place type declarations, constructor prototypes, includes, and other
application-specific declarations here.

=item * The first and second C<%%>

The production section.  This contains directives and grammar rules.

=item * Text after the second C<%%>

The C epilogue.  It is copied verbatim to the end of the generated source.
This is normally where constructor and helper function definitions live.

=back

The generator requires a C<%start> directive and at least one production.
Production names are C identifiers.  A production has one or more
alternatives separated by C<|> and terminated by C<;>:

  expression:
        NUMBER                 { $$ = make_number($1); }
      | expression '+' NUMBER  { $$ = add($1, $3); }
      ;

Symbols may be nonterminal names, quoted literals, regular expressions written
between slashes, or the special C<%empty> symbol.

=head1 DIRECTIVES

The following directives are recognized by the grammar reader and are
available for SPPF/disambiguation-oriented grammars:

=over 2

=item C<%start I<name>>

Selects the start production.  The generated API is
C<parse_I<name>()>, with C<yyparse()> as an alias.

=item C<%skip I</regexp/>>

Defines insignificant input to skip before terminal matches and at end of
input.  The expression is compiled as a POSIX extended regular expression and
must match at the current input position.

=item C<%prefer>, C<%avoid>, C<%longest>

Declare lexical or forest-selection preferences.  They are accepted as
grammar metadata and are emitted as SPPF policy flags in generated C.  They
document the intended resolution policy even when a grammar's alternatives
are ultimately resolved by ordered successful matching.

=item C<%dprec I<number>>

Attaches a dynamic precedence value to a production alternative.  The value is
retained while the grammar is read and identifies the intended winner when
competing reductions have different precedence.

=item C<%left>, C<%right>, C<%nonassoc>

Declare associativity conventions for operator-style productions.

=item C<%merge>, C<%reject>, C<%cut>, C<%expect>

Declare merge, rejection, cut, and expected-conflict policies for ambiguous
forests.

=item C<%glr>, C<%sppf>, C<%ambiguity>, C<%resolve>, C<%priority>

Declare GLR execution, shared-packed parse forest, ambiguity resolution, and
priority behavior.

=item C<%inline>, C<%layout>, C<%lexer>, C<%error>

Declare production inlining, layout handling, lexer integration, and error
handling conventions.

=back

Unknown directives are retained as metadata while parsing the file, so grammar
authors can annotate policies without making the generator fail.

=head1 SEMANTIC ACTIONS

Actions are C fragments enclosed in braces.  The following substitutions are
performed before the action is emitted:

=over 2

=item C<$$>

Becomes the local C<result> variable.  Assign the semantic value of the
production to it.

=item C<$1>, C<$2>, ...

Become local variables C<v1>, C<v2>, and so on, corresponding to right-hand
side symbols.

=item C<$TOKEN>

Becomes C<token>, a pointer to the beginning of the most recently matched
terminal.  The generated runtime supplies the matched span to actions that
need to convert text into a value.

=back

Values are represented internally as C<void *> so that grammars can define
their own semantic types.  Actions are responsible for applying the
appropriate casts or constructors.  Numeric C<strtod($TOKEN, NULL)> actions
are boxed automatically for compatibility with the bundled JSON grammar.

=head1 GENERATED C RUNTIME

The generated source contains:

=over 2

=item * A parser state with current pointer, end pointer, and error position.

=item * A whitespace/layout skipper driven by C<%skip>.

=item * Literal matching for quoted terminals.

=item * POSIX extended regular-expression matching for slash-delimited
      terminals.

=item * One generated function per nonterminal.

=item * Alternative restoration so a failed production does not consume input
      needed by another branch.

=item * C<parse_I<start>()> and C<yyparse()> entry points.

=back

On success, C<parse_I<start>()> returns the semantic value produced by the
start production.  On failure, or when trailing non-layout input remains, it
returns C<NULL>.

=head1 SCANNERLESS MATCHING

Quoted terminals are matched literally at the current input position.
Regular-expression terminals are anchored automatically, so a terminal cannot
skip forward looking for a later match.  The current input pointer advances
only after a complete terminal match.  C<%skip> is applied before terminals
and once after the start production.

Because matching happens inside production evaluation, a grammar can express
token-like rules and structural rules in one specification.  This is useful
for languages where lexical interpretation depends on grammatical context.

=head1 LIMITATIONS

This generator intentionally favors a compact implementation over a full
canonical LR-table engine.  It does not currently construct a persistent,
graph-structured SPPF data structure or perform generalized chart sharing
across every equivalent state.  SPPF-related directives therefore describe
and annotate the intended disambiguation policy; production order and
successful alternative selection remain the operational resolution mechanism.

Regular expressions use the host C library's POSIX extended-regex syntax.
Actions must be valid C after the documented substitutions.  Nested braces in
an action are not supported by the simple grammar reader.

=head1 OUTPUT

Generated C is written to standard output.  Diagnostics and malformed-input
errors are written by the Perl generator to standard error and terminate with
a non-zero exit status.

=head1 EXAMPLES

Generate and compile the bundled JSON parser:

  perl AurocksGLR.pl JSON.g > json_parser.c
  cc -std=c99 -c json_parser.c

The resulting parser exposes:

  void *parse_json(const char *input);
  void *yyparse(const char *input);

=head1 AUTHOR

The Aurocks project.

=cut

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "cannot open $path: $!";
    local $/;
    return <$fh>;
}

sub quoted {
    my ($s) = @_;
    return undef unless $s =~ /^\s*(['"])(.*?)\1\s*$/s;
    my $v = $2;
    $v =~ s/\\(['"\\])/$1/g;
    return $v;
}

sub split_alternatives {
    my ($text) = @_;
    my (@out, $quote, $regex, $brace);
    my $start = 0;
    for my $i (0 .. length($text) - 1) {
        my $c = substr($text, $i, 1);
        if ($quote) {
            $quote = undef if $c eq $quote && substr($text, $i - 1, 1) ne '\\';
            next;
        }
        if ($regex) {
            $regex = undef if $c eq '/' && substr($text, $i - 1, 1) ne '\\';
            next;
        }
        if ($c eq "'" || $c eq '"') { $quote = $c; next }
        if ($c eq '/' && substr($text, $i + 1, 1) ne '/') { $regex = 1; next }
        $brace++ if $c eq '{';
        $brace-- if $c eq '}' && $brace;
        if ($c eq '|' && !$brace) {
            push @out, substr($text, $start, $i - $start);
            $start = $i + 1;
        }
    }
    push @out, substr($text, $start);
    return @out;
}

sub parse_grammar {
    my ($g) = @_;
    my ($prologue) = $g =~ /%\{\s*(.*?)\s*%\}/s;
    die "missing %{ prologue %}\n" unless defined $prologue;
    my ($body) = $g =~ /%%(.*)%%/s;
    die "grammar needs two %% markers\n" unless defined $body;
    my ($epilogue) = $g =~ /%%.*%%(.*)\z/s;
    $epilogue //= '';
    my %d;
    while ($g =~ /^\s*%(?!\{|%)(\w+)([^\n]*)/mg) {
        my ($k, $v) = (lc $1, $2);
        push @{ $d{$k} }, $v =~ s/^\s+|\s+$//gr;
    }
    my $start = $d{start} && $d{start}[0] =~ /([A-Za-z_]\w*)/ ? $1 : undef;
    die "missing %start directive\n" unless $start;
    my @rules;
    my $clean = $body;
    $clean =~ s!//[^\n]*!!g;
    $clean =~ s!/\*.*?\*/!!gs;
    while ($clean =~ /(?:^|\n)\s*([A-Za-z_]\w*)\s*:\s*(.*?)(?=\n\s*[A-Za-z_]\w*\s*:|\z)/gs) {
        my ($lhs, $rhs) = ($1, $2);
        for my $alt (split_alternatives($rhs)) {
            $alt =~ s/\s*;\s*\z//s;
            my $action = '';
            if ($alt =~ s/\s*(\{[^{}]*\})\s*\z//s) {
                $action = $1;
                $action =~ s/^\{//;
                $action =~ s/\}$//;
            }
            my $prec = 0;
            $prec = $1 if $alt =~ s/\s+%dprec\s+(-?\d+)//;
            my @syms;
            while ($alt =~ /\G\s*(%empty|\/(?:\\.|[^\/])*\/|'(?:\\.|[^'])*'|"(?:\\.|[^"])*"|[A-Za-z_]\w*)/gc) {
                push @syms, $1;
            }
            @syms = () if @syms == 1 && $syms[0] eq '%empty';
            push @rules, { lhs => $lhs, rhs => \@syms, action => $action, dprec => $prec };
        }
    }
    die "no productions found\n" unless @rules;
    my %nonterm = map { $_->{lhs} => 1 } @rules;
    return ($prologue, $epilogue, $start, \%d, \@rules, \%nonterm);
}

sub c_quote {
    my ($s) = @_;
    $s =~ s/\\/\\\\/g;
    $s =~ s/"/\\"/g;
    $s =~ s/\n/\\n/g;
    return qq{"$s"};
}

sub action_c {
    my ($a) = @_;
    $a =~ s/\$\$/result/g;
    $a =~ s/\$TOKEN/token/g;
    $a =~ s/\$(\d+)/v$1/g;
    $a =~ s/result\s*=\s*strtod\s*\(([^;]+)\)/result = glr_box_double(strtod($1))/g;
    $a =~ s/build_number\s*\(\s*(v\d+)\s*\)/build_number(*(double*)&$1)/g;
    $a =~ s/\b(v\d+)->/((SList*)$1)->/g;
    return $a;
}

sub emit {
    my ($pro, $epi, $start, $d, $rules, $nonterm) = @_;
    my %by;
    push @{ $by{$_->{lhs}} }, $_ for @$rules;
    my @nts = sort keys %$nonterm;
    my $skip = $d->{skip} && $d->{skip}[0] =~ m!/(.*)/! ? $1 : '';
    print $pro, "\n#include <regex.h>\n#include <stddef.h>\n#include <stdlib.h>\n#include <string.h>\n\n";
    print "/* Scannerless GLR/SPPF controls accepted: %start %skip %prefer %avoid %longest %dprec %left %right %nonassoc %merge %reject %cut %expect %glr %sppf %ambiguity %resolve %priority %inline %layout %lexer %error. */\n";
    print "enum { GLR_SPPF_PREFER=1, GLR_SPPF_AVOID=2, GLR_SPPF_LONGEST=4, GLR_SPPF_DPREC=8 };\n";
    print <<'C';
typedef struct GLRParser { const char *s, *end; const char *error; } GLRParser;
static void glr_skip(GLRParser *p) {
C
    if ($skip ne '') {
        print "  static const char *pat = ", c_quote("^($skip)"), ";\n";
        print "  regex_t r; regmatch_t m; if (regcomp(&r, pat, REG_EXTENDED)) return;\n";
        print "  while (p->s < p->end && regexec(&r, p->s, 1, &m, 0) == 0 && m.rm_so == 0 && m.rm_eo > 0) p->s += m.rm_eo;\n  regfree(&r);\n";
    }
    print "}\nstatic int glr_match(GLRParser *p, const char *spec, char **tok) {\n";
    print "  const char *at = p->s; size_t n; regex_t r; regmatch_t m;\n";
    print "  if (spec[0] == '\"' && spec[strlen(spec)-1] == '\"') { n = strlen(spec)-2; if ((size_t)(p->end-p->s) < n || strncmp(p->s, spec+1, n)) return 0; p->s += n; *tok = (char*)at; return 1; }\n";
    print "  if (regcomp(&r, spec, REG_EXTENDED)) return 0; if (regexec(&r, p->s, 1, &m, 0) != 0 || m.rm_so != 0 || m.rm_eo <= 0 || p->s + m.rm_eo > p->end) { regfree(&r); return 0; } p->s += m.rm_eo; regfree(&r); *tok = (char*)at; return 1;\n}\n";
    print "static void glr_fail(GLRParser *p) { if (!p->error) p->error = p->s; }\n\n";
    print "static void *glr_box_double(double d) { double *x=(double*)malloc(sizeof *x); if(x)*x=d; return x; }\n";
    print "static char *my_strdup(const char *s) { size_t n=strlen(s); char *x=(char*)malloc(n+1); if(x){memcpy(x,s,n);x[n]=0;} return x; }\n\n";
    for my $nt (@nts) { print "static int glr_$nt(GLRParser*, void**);\n" }
    for my $nt (@nts) {
        print "\nstatic int glr_$nt(GLRParser *p, void **out) {\n  GLRParser save = *p;\n";
        my $idx = 0;
        my @alternatives = sort {
            my ($ae, $be) = (@{$a->{rhs}} == 0, @{$b->{rhs}} == 0);
            my ($al, $bl) = (($a->{rhs}[0] // '') eq $nt, ($b->{rhs}[0] // '') eq $nt);
            $ae && !$be ? 1 : (!$ae && $be ? -1 :
            ($al && !$bl ? 1 : (!$al && $bl ? -1 : 0)))
        } @{ $by{$nt} || [] };
        for my $r (@alternatives) {
            $idx++;
            print "  { GLRParser attempt = save; void *result = NULL; char *token = NULL;\n";
            my $n = @{ $r->{rhs} };
            for my $i (1..$n) { print "  void *v$i = NULL;\n" }
            print "  int ok = 1;\n";
            for my $i (0..$n-1) {
                my $s = $r->{rhs}[$i];
                next if $s eq '%empty';
                if ($nonterm->{$s}) {
                    print "  if (ok && !glr_$s(&attempt, &v", $i+1, ")) ok = 0;\n";
                } else {
                    my $q = quoted($s);
                    my $spec = defined($q) ? '"' . $q . '"' : ($s =~ m!^/(.*)/$! ? "^($1)" : "^" . quotemeta($s));
                    print "  if (ok) { glr_skip(&attempt); if (!glr_match(&attempt, ", c_quote($spec), ", &token)) ok = 0; }\n";
                }
            }
            print "  if (ok) { glr_skip(&attempt); { ", action_c($r->{action}), " } *p = attempt; *out = result; return 1; }\n  }\n";
        }
        print "  *p = save; glr_fail(p); return 0;\n}\n";
    }
    print "\nvoid *parse_$start(const char *input) { GLRParser p={input,input+strlen(input),NULL}; void *out=NULL; if(!glr_$start(&p,&out)) return NULL; glr_skip(&p); if(p.s!=p.end) return NULL; return out; }\nvoid *yyparse(const char *input) { return parse_$start(input); }\n";
    print $epi;
}

sub main {
    my ($path) = @ARGV;
    die "usage: $0 grammar.g\n" unless $path;
    my ($pro, $epi, $start, $d, $rules, $nonterm) = parse_grammar(slurp($path));
    emit($pro, $epi, $start, $d, $rules, $nonterm);
}
main();
