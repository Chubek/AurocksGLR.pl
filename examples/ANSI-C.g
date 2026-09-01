# AurocksGLR Grammar for ANSI C -- formatter subset

%{

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

typedef struct Fmt Fmt;
typedef struct FmtList FmtList;

struct Fmt
{
   char *text;
   int   prec;
};

struct FmtList
{
   Fmt      *item;
   FmtList  *next;
};

enum
{
   C_PREC_ATOM = 100,
   C_PREC_POSTFIX = 90,
   C_PREC_UNARY = 80,
   C_PREC_MUL = 70,
   C_PREC_ADD = 60,
   C_PREC_SHIFT = 55,
   C_PREC_REL = 50,
   C_PREC_EQ = 45,
   C_PREC_BITAND = 40,
   C_PREC_BITXOR = 35,
   C_PREC_BITOR = 30,
   C_PREC_AND = 25,
   C_PREC_OR = 20,
   C_PREC_ASSIGN = 10
};

static char *c_cat (const char *first, ...);
static char *c_indent (const char *text, int depth);
static Fmt  *c_make (char *text, int prec);
static Fmt  *c_atom (char *text);
static Fmt  *c_join (FmtList *list, const char *separator);
static Fmt  *c_bin (Fmt *left, const char *op, Fmt *right, int prec, int assoc);
static Fmt  *c_unary (const char *op, Fmt *expr, int prec);
static Fmt  *c_group (Fmt *expr);
static Fmt  *c_call (Fmt *base, Fmt *args);
static Fmt  *c_index (Fmt *base, Fmt *index);
static Fmt  *c_field (Fmt *base, const char *name);
static Fmt  *c_postfix (Fmt *base, const char *suffix);
static Fmt  *c_block (FmtList *items);
static Fmt  *c_if (Fmt *condition, Fmt *then_body, Fmt *else_body);
static Fmt  *c_while (Fmt *condition, Fmt *body);
static Fmt  *c_for (Fmt *init, Fmt *condition, Fmt *step, Fmt *body);
static Fmt  *c_return (Fmt *values);
static Fmt  *c_break (void);
static Fmt  *c_continue (void);
static Fmt  *c_expr_stmt (Fmt *expr);
static Fmt  *c_declspec (FmtList *specifiers);
static Fmt  *c_declarator (Fmt *pointer, Fmt *direct);
static Fmt  *c_pointer (Fmt *tail);
static Fmt  *c_function (Fmt *specifiers, Fmt *declarator, Fmt *body);
static Fmt  *c_declaration (Fmt *specifiers, FmtList *init_declarators);
static Fmt  *c_initializer_list (FmtList *items);
static Fmt  *c_params (FmtList *items);
static FmtList *fmt_list_new (Fmt *item);
static FmtList *fmt_list_append (FmtList *list, Fmt *item);
static void emit_formatted (Fmt *node);

static char *
c_dup (const char *text)
{
   size_t length = strlen (text);
   char *copy = malloc (length + 1);
   if (copy == NULL)
      return NULL;
   memcpy (copy, text, length + 1);
   return copy;
}

static char *
c_cat (const char *first, ...)
{
   va_list ap;
   const char *piece = first;
   size_t length = 1;

   va_start (ap, first);
   while (piece != NULL)
   {
      length += strlen (piece);
      piece = va_arg (ap, const char *);
   }
   va_end (ap);

   char *text = malloc (length);
   if (text == NULL)
      return NULL;

   text[0] = '\0';
   va_start (ap, first);
   piece = first;
   while (piece != NULL)
   {
      strcat (text, piece);
      piece = va_arg (ap, const char *);
   }
   va_end (ap);
   return text;
}

static char *
c_indent (const char *text, int depth)
{
   size_t indent_width = (size_t) depth * 2;
   size_t length = 1;
   int at_line_start = 1;

   for (const char *scan = text; *scan != '\0'; scan++)
   {
      if (at_line_start)
         length += indent_width;
      length++;
      at_line_start = (*scan == '\n');
   }

   char *indented = malloc (length);
   if (indented == NULL)
      return NULL;

   char *out = indented;
   at_line_start = 1;
   for (const char *scan = text; *scan != '\0'; scan++)
   {
      if (at_line_start)
      {
         for (size_t i = 0; i < indent_width; i++)
            *out++ = ' ';
         at_line_start = 0;
      }

      *out++ = *scan;
      if (*scan == '\n')
         at_line_start = 1;
   }

   *out = '\0';
   return indented;
}

static Fmt *
c_make (char *text, int prec)
{
   Fmt *node = malloc (sizeof *node);
   node->text = text;
   node->prec = prec;
   return node;
}

static Fmt *
c_atom (char *text)
{
   return c_make (text, C_PREC_ATOM);
}

static FmtList *
fmt_list_new (Fmt *item)
{
   FmtList *node = malloc (sizeof *node);
   node->item = item;
   node->next = NULL;
   return node;
}

static FmtList *
fmt_list_append (FmtList *list, Fmt *item)
{
   FmtList *node = fmt_list_new (item);
   if (list == NULL)
      return node;

   FmtList *tail = list;
   while (tail->next != NULL)
      tail = tail->next;
   tail->next = node;
   return list;
}

static Fmt *
c_join (FmtList *list, const char *separator)
{
   size_t length = 1;
   FmtList *scan = list;

   while (scan != NULL)
   {
      length += strlen (scan->item->text);
      if (scan->next != NULL)
         length += strlen (separator);
      scan = scan->next;
   }

   char *text = malloc (length);
   if (text == NULL)
      return c_make (c_dup (""), C_PREC_ATOM);

   text[0] = '\0';
   scan = list;
   while (scan != NULL)
   {
      strcat (text, scan->item->text);
      if (scan->next != NULL)
         strcat (text, separator);
      scan = scan->next;
   }
   return c_make (text, C_PREC_ATOM);
}

static Fmt *
c_bin (Fmt *left, const char *op, Fmt *right, int prec, int assoc)
{
   char *lhs = left->text;
   char *rhs = right->text;
   char *lhs_wrap = NULL;
   char *rhs_wrap = NULL;

   if (left->prec < prec || (assoc == 1 && left->prec == prec))
   {
      lhs_wrap = c_cat ("(", lhs, ")", NULL);
      lhs = lhs_wrap;
   }

   if (right->prec < prec || (assoc == 0 && right->prec == prec))
   {
      rhs_wrap = c_cat ("(", rhs, ")", NULL);
      rhs = rhs_wrap;
   }

   Fmt *node = c_make (c_cat (lhs, op, rhs, NULL), prec);
   free (lhs_wrap);
   free (rhs_wrap);
   return node;
}

static Fmt *
c_unary (const char *op, Fmt *expr, int prec)
{
   char *body = expr->prec < prec ? c_cat ("(", expr->text, ")", NULL) : expr->text;
   return c_make (c_cat (op, body, NULL), prec);
}

static Fmt *
c_group (Fmt *expr)
{
   return c_make (c_cat ("(", expr->text, ")", NULL), C_PREC_ATOM);
}

static Fmt *
c_call (Fmt *base, Fmt *args)
{
   return c_make (c_cat (base->text, args->text, NULL), C_PREC_POSTFIX);
}

static Fmt *
c_index (Fmt *base, Fmt *index)
{
   return c_make (c_cat (base->text, "[", index->text, "]", NULL), C_PREC_POSTFIX);
}

static Fmt *
c_field (Fmt *base, const char *name)
{
   return c_make (c_cat (base->text, ".", name, NULL), C_PREC_POSTFIX);
}

static Fmt *
c_postfix (Fmt *base, const char *suffix)
{
   return c_make (c_cat (base->text, suffix, NULL), C_PREC_POSTFIX);
}

static Fmt *
c_block (FmtList *items)
{
   Fmt *joined = c_join (items, "\n");
   if (joined->text[0] == '\0')
      return c_atom (c_dup ("{\n}"));
   return c_make (c_cat ("{\n", c_indent (joined->text, 1), "\n}", NULL), 0);
}

static Fmt *
c_if (Fmt *condition, Fmt *then_body, Fmt *else_body)
{
   char *text;
   if (else_body == NULL)
      text = c_cat ("if (", condition->text, ")\n", c_indent (then_body->text, 1), NULL);
   else
      text = c_cat ("if (", condition->text, ")\n", c_indent (then_body->text, 1),
         "\nelse\n", c_indent (else_body->text, 1), NULL);
   return c_make (text, 0);
}

static Fmt *
c_while (Fmt *condition, Fmt *body)
{
   return c_make (c_cat ("while (", condition->text, ")\n", c_indent (body->text, 1), NULL), 0);
}

static Fmt *
c_for (Fmt *init, Fmt *condition, Fmt *step, Fmt *body)
{
   char *text;
   if (step == NULL)
      text = c_cat ("for (", init->text, "; ", condition->text, "; )\n", c_indent (body->text, 1), NULL);
   else
      text = c_cat ("for (", init->text, "; ", condition->text, "; ", step->text, ")\n",
         c_indent (body->text, 1), NULL);
   return c_make (text, 0);
}

static Fmt *
c_return (Fmt *values)
{
   if (values == NULL || values->text[0] == '\0')
      return c_atom (c_dup ("return;"));
   return c_make (c_cat ("return ", values->text, ";", NULL), 0);
}

static Fmt *
c_break (void)
{
   return c_atom (c_dup ("break;"));
}

static Fmt *
c_continue (void)
{
   return c_atom (c_dup ("continue;"));
}

static Fmt *
c_expr_stmt (Fmt *expr)
{
   if (expr == NULL || expr->text[0] == '\0')
      return c_atom (c_dup (";"));
   return c_make (c_cat (expr->text, ";", NULL), 0);
}

static Fmt *
c_declspec (FmtList *specifiers)
{
   return c_join (specifiers, " ");
}

static Fmt *
c_declarator (Fmt *pointer, Fmt *direct)
{
   if (pointer == NULL || pointer->text[0] == '\0')
      return direct;
   if (direct->text[0] == '(')
      return c_make (c_cat ("(", pointer->text, direct->text + 1, NULL), C_PREC_ATOM);
   return c_make (c_cat (pointer->text, direct->text[0] == '\0' ? "" : " ", direct->text, NULL), C_PREC_ATOM);
}

static Fmt *
c_pointer (Fmt *tail)
{
   if (tail == NULL || tail->text[0] == '\0')
      return c_atom (c_dup ("*"));
   return c_make (c_cat ("*", tail->text, NULL), C_PREC_ATOM);
}

static Fmt *
c_function (Fmt *specifiers, Fmt *declarator, Fmt *body)
{
   return c_make (c_cat (specifiers->text, " ", declarator->text, "\n", body->text, NULL), 0);
}

static Fmt *
c_declaration (Fmt *specifiers, FmtList *init_declarators)
{
   Fmt *joined = c_join (init_declarators, ", ");
   if (joined->text[0] == '\0')
      return c_make (c_cat (specifiers->text, ";", NULL), 0);
   return c_make (c_cat (specifiers->text, " ", joined->text, ";", NULL), 0);
}

static Fmt *
c_initializer_list (FmtList *items)
{
   return c_join (items, ", ");
}

static Fmt *
c_params (FmtList *items)
{
   Fmt *joined = c_join (items, ", ");
   return c_make (c_cat ("(", joined->text, ")", NULL), C_PREC_POSTFIX);
}

static void
emit_formatted (Fmt *node)
{
   fputs (node->text, stdout);
   fputc ('\n', stdout);
}

%}

%target Go
%start translation_unit
%skip /[ \t\r\n]+|\/\/[^\n]*|\/\*([^*]|\*+[^*\/])*\*+\//

%%

translation_unit:
     %empty                      { $$ = c_atom (c_dup ("")); }
   | external_list                { $$ = c_join ($1, "\n"); }
   ;

external_list:
     external_declaration         { $$ = fmt_list_new ($1); }
   | external_list external_declaration
                                 { $$ = fmt_list_append ($1, $2); }
   ;

external_declaration:
     function_definition          { $$ = $1; }
   | declaration                  { $$ = $1; }
   ;

function_definition:
     declspec declarator compound_statement
                                 { $$ = c_function ($1, $2, $3); }
   ;

declaration:
     declspec ';'                 { $$ = c_declaration ($1, NULL); }
   | declspec init_declarator_list ';'
                                 { $$ = c_declaration ($1, $2); }
   ;

init_declarator_list:
     init_declarator              { $$ = fmt_list_new ($1); }
   | init_declarator_list ',' init_declarator
                                 { $$ = fmt_list_append ($1, $3); }
   ;

init_declarator:
     declarator                   { $$ = $1; }
   | declarator '=' initializer   { $$ = c_make (c_cat ($1->text, " = ", $3->text, NULL), 0); }
   ;

initializer:
     assignment_expression        { $$ = $1; }
   | '{' initializer_list '}'      { $$ = c_make (c_cat ("{", $2->text, "}", NULL), C_PREC_ATOM); }
   ;

initializer_list:
     initializer                  { $$ = fmt_list_new ($1); }
   | initializer_list ',' initializer
                                 { $$ = fmt_list_append ($1, $3); }
   ;

declspec:
     specseq                      { $$ = c_declspec ($1); }
   ;

specseq:
     specifier                    { $$ = fmt_list_new ($1); }
   | specseq specifier            { $$ = fmt_list_append ($1, $2); }
   ;

specifier:
     "const"                      { $$ = c_atom (c_dup ("const")); }
   | "volatile"                   { $$ = c_atom (c_dup ("volatile")); }
   | "static"                     { $$ = c_atom (c_dup ("static")); }
   | "extern"                     { $$ = c_atom (c_dup ("extern")); }
   | "register"                   { $$ = c_atom (c_dup ("register")); }
   | "auto"                       { $$ = c_atom (c_dup ("auto")); }
   | "signed"                     { $$ = c_atom (c_dup ("signed")); }
   | "unsigned"                   { $$ = c_atom (c_dup ("unsigned")); }
   | "short"                      { $$ = c_atom (c_dup ("short")); }
   | "long"                       { $$ = c_atom (c_dup ("long")); }
   | "int"                        { $$ = c_atom (c_dup ("int")); }
   | "char"                       { $$ = c_atom (c_dup ("char")); }
   | "float"                      { $$ = c_atom (c_dup ("float")); }
   | "double"                     { $$ = c_atom (c_dup ("double")); }
   | "void"                       { $$ = c_atom (c_dup ("void")); }
   | "struct"                     { $$ = c_atom (c_dup ("struct")); }
   | "union"                      { $$ = c_atom (c_dup ("union")); }
   | "enum"                       { $$ = c_atom (c_dup ("enum")); }
   | NAME                         { $$ = $1; }
   ;

declarator:
     pointer_opt direct_declarator { $$ = c_declarator ($1, $2); }
   ;

pointer_opt:
     %empty                       { $$ = NULL; }
   | '*' pointer_opt              { $$ = c_pointer ($2); }
   ;

direct_declarator:
     NAME                         { $$ = $1; }
   | '(' declarator ')'            { $$ = c_group ($2); }
   | direct_declarator '[' expr_opt ']'  { $$ = c_make (c_cat ($1->text, "[", $3 == NULL ? "" : $3->text, "]", NULL), C_PREC_POSTFIX); }
   | direct_declarator '(' param_type_list_opt ')' { $$ = c_make (c_cat ($1->text, "(", $3 == NULL ? "" : $3->text, ")", NULL), C_PREC_POSTFIX); }
   ;

param_type_list_opt:
     %empty                       { $$ = NULL; }
   | param_type_list              { $$ = c_join ($1, ", "); }
   ;

param_type_list:
     param_declaration            { $$ = fmt_list_new ($1); }
   | param_type_list ',' param_declaration
                                 { $$ = fmt_list_append ($1, $3); }
   ;

param_declaration:
     declspec declarator_opt      { $$ = c_make (c_cat ($1->text, $2 == NULL ? "" : " ", $2 == NULL ? "" : $2->text, NULL), 0); }
   ;

declarator_opt:
     %empty                       { $$ = NULL; }
   | declarator                    { $$ = $1; }
   ;

compound_statement:
     '{' block_items_opt '}'      { $$ = c_block ($2); }
   ;

block_items_opt:
     %empty                       { $$ = NULL; }
   | block_items                  { $$ = $1; }
   ;

block_items:
     block_item                   { $$ = fmt_list_new ($1); }
   | block_items block_item       { $$ = fmt_list_append ($1, $2); }
   ;

block_item:
     declaration                  { $$ = $1; }
   | statement                    { $$ = $1; }
   ;

statement:
     compound_statement           { $$ = $1; }
   | expr_opt ';'                 { $$ = c_expr_stmt ($1); }
   | "if" '(' expr ')' statement else_opt
                                 { $$ = c_if ($3, $5, $6); }
   | "while" '(' expr ')' statement
                                 { $$ = c_while ($3, $5); }
   | "for" '(' expr_opt ';' expr_opt ';' expr_opt ')' statement
                                 { $$ = c_for ($3 == NULL ? c_atom (c_dup ("")) : $3, $5 == NULL ? c_atom (c_dup ("")) : $5, $7, $9); }
   | "return" expr_opt ';'       { $$ = c_return ($2); }
   | "break" ';'                 { $$ = c_break (); }
   | "continue" ';'              { $$ = c_continue (); }
   ;

else_opt:
     %empty                       { $$ = NULL; }
   | "else" statement             { $$ = $2; }
   ;

expr_opt:
     %empty                       { $$ = NULL; }
   | expr                         { $$ = $1; }
   ;

expr:
     assignment_expression        { $$ = $1; }
   | expr ',' assignment_expression
                                 { $$ = c_bin ($1, ", ", $3, C_PREC_ASSIGN, 0); }
   ;

assignment_expression:
     logical_or_expression        { $$ = $1; }
   | unary_expression '=' assignment_expression
                                 { $$ = c_bin ($1, " = ", $3, C_PREC_ASSIGN, 1); }
   ;

logical_or_expression:
     logical_or_expression "||" logical_and_expression
                                 { $$ = c_bin ($1, " || ", $3, C_PREC_OR, 0); }
   | logical_and_expression       { $$ = $1; }
   ;

logical_and_expression:
     logical_and_expression "&&" bitwise_or_expression
                                 { $$ = c_bin ($1, " && ", $3, C_PREC_AND, 0); }
   | bitwise_or_expression        { $$ = $1; }
   ;

bitwise_or_expression:
     bitwise_or_expression '|' bitwise_xor_expression
                                 { $$ = c_bin ($1, " | ", $3, C_PREC_BITOR, 0); }
   | bitwise_xor_expression       { $$ = $1; }
   ;

bitwise_xor_expression:
     bitwise_xor_expression '^' bitwise_and_expression
                                 { $$ = c_bin ($1, " ^ ", $3, C_PREC_BITXOR, 0); }
   | bitwise_and_expression       { $$ = $1; }
   ;

bitwise_and_expression:
     bitwise_and_expression '&' equality_expression
                                 { $$ = c_bin ($1, " & ", $3, C_PREC_BITAND, 0); }
   | equality_expression          { $$ = $1; }
   ;

equality_expression:
     equality_expression "==" relational_expression
                                 { $$ = c_bin ($1, " == ", $3, C_PREC_EQ, 0); }
   | equality_expression "!=" relational_expression
                                 { $$ = c_bin ($1, " != ", $3, C_PREC_EQ, 0); }
   | relational_expression        { $$ = $1; }
   ;

relational_expression:
     relational_expression '<' shift_expression
                                 { $$ = c_bin ($1, " < ", $3, C_PREC_REL, 0); }
   | relational_expression '>' shift_expression
                                 { $$ = c_bin ($1, " > ", $3, C_PREC_REL, 0); }
   | relational_expression "<=" shift_expression
                                 { $$ = c_bin ($1, " <= ", $3, C_PREC_REL, 0); }
   | relational_expression ">=" shift_expression
                                 { $$ = c_bin ($1, " >= ", $3, C_PREC_REL, 0); }
   | shift_expression             { $$ = $1; }
   ;

shift_expression:
     shift_expression "<<" additive_expression
                                 { $$ = c_bin ($1, " << ", $3, C_PREC_SHIFT, 0); }
   | shift_expression ">>" additive_expression
                                 { $$ = c_bin ($1, " >> ", $3, C_PREC_SHIFT, 0); }
   | additive_expression          { $$ = $1; }
   ;

additive_expression:
     additive_expression '+' multiplicative_expression
                                 { $$ = c_bin ($1, " + ", $3, C_PREC_ADD, 0); }
   | additive_expression '-' multiplicative_expression
                                 { $$ = c_bin ($1, " - ", $3, C_PREC_ADD, 0); }
   | multiplicative_expression    { $$ = $1; }
   ;

multiplicative_expression:
     multiplicative_expression '*' unary_expression
                                 { $$ = c_bin ($1, " * ", $3, C_PREC_MUL, 0); }
   | multiplicative_expression '/' unary_expression
                                 { $$ = c_bin ($1, " / ", $3, C_PREC_MUL, 0); }
   | multiplicative_expression '%' unary_expression
                                 { $$ = c_bin ($1, " % ", $3, C_PREC_MUL, 0); }
   | unary_expression             { $$ = $1; }
   ;

unary_expression:
     '!' unary_expression         { $$ = c_unary ("!", $2, C_PREC_UNARY); }
   | '-' unary_expression         { $$ = c_unary ("-", $2, C_PREC_UNARY); }
   | '+' unary_expression         { $$ = c_unary ("+", $2, C_PREC_UNARY); }
   | '~' unary_expression         { $$ = c_unary ("~", $2, C_PREC_UNARY); }
   | "sizeof" unary_expression    { $$ = c_unary ("sizeof ", $2, C_PREC_UNARY); }
   | postfix_expression           { $$ = $1; }
   ;

postfix_expression:
     primary_expression           { $$ = $1; }
   | postfix_expression '(' arg_expr_list_opt ')'  { $$ = c_call ($1, c_params ($3)); }
   | postfix_expression '[' expr ']'               { $$ = c_index ($1, $3); }
   | postfix_expression '.' NAME                   { $$ = c_field ($1, $3->text); }
   | postfix_expression "->" NAME                  { $$ = c_make (c_cat ($1->text, "->", $3->text, NULL), C_PREC_POSTFIX); }
   | postfix_expression "++"                       { $$ = c_postfix ($1, "++"); }
   | postfix_expression "--"                       { $$ = c_postfix ($1, "--"); }
   ;

primary_expression:
     NAME                         { $$ = $1; }
   | NUMBER                       { $$ = $1; }
   | STRING                       { $$ = $1; }
   | '(' expr ')'                 { $$ = c_group ($2); }
   ;

arg_expr_list_opt:
     %empty                       { $$ = NULL; }
   | arg_expr_list                { $$ = $1; }
   ;

arg_expr_list:
     assignment_expression        { $$ = fmt_list_new ($1); }
   | arg_expr_list ',' assignment_expression
                                 { $$ = fmt_list_append ($1, $3); }
   ;

NAME:
     /[A-Za-z_][A-Za-z0-9_]*/      { $$ = c_atom (c_dup ($TOKEN)); }
   ;

NUMBER:
     /0[xX][0-9A-Fa-f]+(\.[0-9A-Fa-f]+)?([pP][+-]?[0-9]+)?|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/
                                 { $$ = c_atom (c_dup ($TOKEN)); }
   ;

STRING:
     /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/  { $$ = c_atom (c_dup ($TOKEN)); }
   ;

%%

static void
emit_formatted (Fmt *node)
{
   fputs (node->text, stdout);
   fputc ('\n', stdout);
}

int
main (int argc, char **argv)
{
   FILE *infile = NULL;

   if (argc < 2)
   {
      fputs ("No input file given\n", stderr);
      return EXIT_FAILURE;
   }

   infile = fopen (argv[1], "r");
   if (infile == NULL)
   {
      fputs ("Failed to open file\n", stderr);
      return EXIT_FAILURE;
   }

   fseek (infile, 0, SEEK_END);
   long length = ftell (infile);
   fseek (infile, 0, SEEK_SET);

   char *contents = malloc ((size_t) length + 1);
   fread (contents, 1, (size_t) length, infile);
   contents[length] = '\0';
   fclose (infile);

   Fmt *formatted = (Fmt *) yyparse (contents);
   free (contents);
   emit_formatted (formatted);
   return 0;
}
