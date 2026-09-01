# AurocksGLR Grammar for Lua -- formatter subset

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
   LUA_PREC_ATOM = 100,
   LUA_PREC_POW = 90,
   LUA_PREC_UNARY = 80,
   LUA_PREC_MUL = 70,
   LUA_PREC_ADD = 60,
   LUA_PREC_CONCAT = 50,
   LUA_PREC_CMP = 40,
   LUA_PREC_AND = 30,
   LUA_PREC_OR = 20
};

static char *lua_cat (const char *first, ...);
static char *lua_indent (const char *text, int depth);
static Fmt  *lua_make (char *text, int prec);
static Fmt  *lua_atom (char *text);
static Fmt  *lua_join (FmtList *list, const char *separator);
static Fmt  *lua_bin (Fmt *left, const char *op, Fmt *right, int prec, int assoc);
static Fmt  *lua_unary (const char *op, Fmt *expr, int prec);
static Fmt  *lua_group (Fmt *expr);
static Fmt  *lua_call (Fmt *base, Fmt *args);
static Fmt  *lua_method_call (Fmt *base, const char *name, Fmt *args);
static Fmt  *lua_index (Fmt *base, Fmt *index);
static Fmt  *lua_field (Fmt *base, const char *name);
static Fmt  *lua_table (FmtList *fields);
static Fmt  *lua_stmt (const char *text);
static Fmt  *lua_do (Fmt *body);
static Fmt  *lua_while (Fmt *condition, Fmt *body);
static Fmt  *lua_repeat (Fmt *body, Fmt *condition);
static Fmt  *lua_for_numeric (char *name, Fmt *start, Fmt *finish, Fmt *step, Fmt *body);
static Fmt  *lua_for_generic (Fmt *names, Fmt *values, Fmt *body);
static Fmt  *lua_function (char *name, Fmt *params, Fmt *body, int is_local);
static Fmt  *lua_if (Fmt *condition, Fmt *then_body, Fmt *else_body);
static Fmt  *lua_assign (Fmt *names, Fmt *values);
static Fmt  *lua_local (Fmt *names, Fmt *values);
static Fmt  *lua_return (FmtList *values);
static Fmt  *lua_break_stmt (void);
static Fmt  *lua_block (FmtList *statements);
static FmtList *fmt_list_new (Fmt *item);
static FmtList *fmt_list_append (FmtList *list, Fmt *item);
static void emit_formatted (Fmt *node);

static char *
lua_dup (const char *text)
{
   size_t length = strlen (text);
   char *copy = malloc (length + 1);
   if (copy == NULL)
      return NULL;
   memcpy (copy, text, length + 1);
   return copy;
}

static char *
lua_cat (const char *first, ...)
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
lua_indent (const char *text, int depth)
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
lua_make (char *text, int prec)
{
   Fmt *node = malloc (sizeof *node);
   node->text = text;
   node->prec = prec;
   return node;
}

static Fmt *
lua_atom (char *text)
{
   return lua_make (text, LUA_PREC_ATOM);
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
lua_join (FmtList *list, const char *separator)
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
      return lua_make (lua_dup (""), LUA_PREC_ATOM);

   text[0] = '\0';
   scan = list;
   while (scan != NULL)
   {
      strcat (text, scan->item->text);
      if (scan->next != NULL)
         strcat (text, separator);
      scan = scan->next;
   }
   return lua_make (text, LUA_PREC_ATOM);
}

static Fmt *
lua_bin (Fmt *left, const char *op, Fmt *right, int prec, int assoc)
{
   char *lhs = left->text;
   char *rhs = right->text;
   char *lhs_wrap = NULL;
   char *rhs_wrap = NULL;

   if (left->prec < prec || (assoc == 1 && left->prec == prec))
   {
      lhs_wrap = lua_cat ("(", lhs, ")", NULL);
      lhs = lhs_wrap;
   }

   if (right->prec < prec || (assoc == 0 && right->prec == prec))
   {
      rhs_wrap = lua_cat ("(", rhs, ")", NULL);
      rhs = rhs_wrap;
   }

   Fmt *node = lua_make (lua_cat (lhs, op, rhs, NULL), prec);
   free (lhs_wrap);
   free (rhs_wrap);
   return node;
}

static Fmt *
lua_unary (const char *op, Fmt *expr, int prec)
{
   char *body = expr->prec < prec ? lua_cat ("(", expr->text, ")", NULL) : expr->text;
   return lua_make (lua_cat (op, body, NULL), prec);
}

static Fmt *
lua_group (Fmt *expr)
{
   return lua_make (lua_cat ("(", expr->text, ")", NULL), LUA_PREC_ATOM);
}

static Fmt *
lua_call (Fmt *base, Fmt *args)
{
   return lua_make (lua_cat (base->text, args->text, NULL), LUA_PREC_ATOM);
}

static Fmt *
lua_method_call (Fmt *base, const char *name, Fmt *args)
{
   return lua_make (lua_cat (base->text, ":", name, args->text, NULL), LUA_PREC_ATOM);
}

static Fmt *
lua_index (Fmt *base, Fmt *index)
{
   return lua_make (lua_cat (base->text, "[", index->text, "]", NULL), LUA_PREC_ATOM);
}

static Fmt *
lua_field (Fmt *base, const char *name)
{
   return lua_make (lua_cat (base->text, ".", name, NULL), LUA_PREC_ATOM);
}

static Fmt *
lua_table (FmtList *fields)
{
   Fmt *joined = lua_join (fields, ", ");
   if (joined->text[0] == '\0')
      return lua_make (lua_dup ("{}"), LUA_PREC_ATOM);
   return lua_make (lua_cat ("{", joined->text, "}", NULL), LUA_PREC_ATOM);
}

static Fmt *
lua_stmt (const char *text)
{
   return lua_make (lua_dup (text), 0);
}

static Fmt *
lua_block (FmtList *statements)
{
   return lua_join (statements, "\n");
}

static Fmt *
lua_do (Fmt *body)
{
   char *text = body->text[0] == '\0'
      ? lua_cat ("do\nend", NULL)
      : lua_cat ("do\n", lua_indent (body->text, 1), "\nend", NULL);
   return lua_make (text, 0);
}

static Fmt *
lua_while (Fmt *condition, Fmt *body)
{
   char *text = body->text[0] == '\0'
      ? lua_cat ("while ", condition->text, " do\nend", NULL)
      : lua_cat ("while ", condition->text, " do\n", lua_indent (body->text, 1), "\nend", NULL);
   return lua_make (text, 0);
}

static Fmt *
lua_repeat (Fmt *body, Fmt *condition)
{
   char *text = body->text[0] == '\0'
      ? lua_cat ("repeat\nuntil ", condition->text, NULL)
      : lua_cat ("repeat\n", lua_indent (body->text, 1), "\nuntil ", condition->text, NULL);
   return lua_make (text, 0);
}

static Fmt *
lua_for_numeric (char *name, Fmt *start, Fmt *finish, Fmt *step, Fmt *body)
{
   char *header;
   if (step == NULL)
      header = lua_cat ("for ", name, " = ", start->text, ", ", finish->text, " do", NULL);
   else
      header = lua_cat ("for ", name, " = ", start->text, ", ", finish->text, ", ", step->text, " do", NULL);

   char *text = body->text[0] == '\0'
      ? lua_cat (header, "\nend", NULL)
      : lua_cat (header, "\n", lua_indent (body->text, 1), "\nend", NULL);
   free (header);
   return lua_make (text, 0);
}

static Fmt *
lua_for_generic (Fmt *names, Fmt *values, Fmt *body)
{
   char *text = body->text[0] == '\0'
      ? lua_cat ("for ", names->text, " in ", values->text, " do\nend", NULL)
      : lua_cat ("for ", names->text, " in ", values->text, " do\n", lua_indent (body->text, 1), "\nend", NULL);
   return lua_make (text, 0);
}

static Fmt *
lua_function (char *name, Fmt *params, Fmt *body, int is_local)
{
   char *header;
   if (is_local)
      header = lua_cat ("local function ", name, "(", params->text, ")", NULL);
   else
      header = lua_cat ("function ", name, "(", params->text, ")", NULL);

   char *text = body->text[0] == '\0'
      ? lua_cat (header, "\nend", NULL)
      : lua_cat (header, "\n", lua_indent (body->text, 1), "\nend", NULL);
   free (header);
   return lua_make (text, 0);
}

static Fmt *
lua_if (Fmt *condition, Fmt *then_body, Fmt *else_body)
{
   char *text;
   if (else_body == NULL)
      text = then_body->text[0] == '\0'
         ? lua_cat ("if ", condition->text, " then\nend", NULL)
         : lua_cat ("if ", condition->text, " then\n", lua_indent (then_body->text, 1), "\nend", NULL);
   else
      text = lua_cat ("if ", condition->text, " then\n",
         then_body->text[0] == '\0' ? "" : lua_indent (then_body->text, 1), "\nelse\n",
         else_body->text[0] == '\0' ? "" : lua_indent (else_body->text, 1), "\nend", NULL);
   return lua_make (text, 0);
}

static Fmt *
lua_assign (Fmt *names, Fmt *values)
{
   return lua_make (lua_cat (names->text, " = ", values->text, NULL), 0);
}

static Fmt *
lua_local (Fmt *names, Fmt *values)
{
   if (values == NULL || values->text[0] == '\0')
      return lua_make (lua_cat ("local ", names->text, NULL), 0);
   return lua_make (lua_cat ("local ", names->text, " = ", values->text, NULL), 0);
}

static Fmt *
lua_return (FmtList *values)
{
   Fmt *joined = lua_join (values, ", ");
   if (joined->text[0] == '\0')
      return lua_make (lua_dup ("return"), 0);
   return lua_make (lua_cat ("return ", joined->text, NULL), 0);
}

static Fmt *
lua_break_stmt (void)
{
   return lua_stmt ("break");
}

static void
emit_formatted (Fmt *node)
{
   fputs (node->text, stdout);
   fputc ('\n', stdout);
}

%}

%target Python
%start chunk
%skip /[ \t\r\n]+|--[^\n]*/

%%

chunk:
     %empty             { $$ = lua_stmt (""); }
   | statlist           { $$ = lua_block ($1); }
   ;

statlist:
     %empty                               { $$ = NULL; }
   | stat                                  { $$ = fmt_list_new ($1); }
   | statlist ';' stat                     { $$ = fmt_list_append ($1, $3); }
   | statlist stat                         { $$ = fmt_list_append ($1, $2); }
   ;

block:
     statlist                              { $$ = lua_block ($1); }
   ;

stat:
     "break"                              { $$ = lua_break_stmt (); }
   | "return" explist                     { $$ = lua_return ($2); }
   | "local" "function" NAME '(' parlist ')' block "end"
                                         { $$ = lua_function ($3->text, $5, $7, 1); }
   | "local" namelist opt_init            { $$ = lua_local (lua_join ($2, ", "), $3); }
   | "function" funcname '(' parlist ')' block "end"
                                         { $$ = lua_function ($2->text, $4, $6, 0); }
   | "do" statlist "end"                  { $$ = lua_do (lua_block ($2)); }
   | "while" expr "do" statlist "end"     { $$ = lua_while ($2, lua_block ($4)); }
   | "repeat" statlist "until" expr       { $$ = lua_repeat (lua_block ($2), $4); }
   | "for" NAME '=' expr ',' expr forstep "do" statlist "end"
                                         { $$ = lua_for_numeric ($2->text, $4, $6, $7, lua_block ($9)); }
   | "for" namelist "in" explist "do" statlist "end"
                                         { $$ = lua_for_generic (lua_join ($2, ", "), lua_join ($4, ", "), lua_block ($6)); }
   | "if" expr "then" statlist elseopt "end"
                                         { $$ = lua_if ($2, lua_block ($4), $5); }
   | varlist '=' explist                  { $$ = lua_assign (lua_join ($1, ", "), lua_join ($3, ", ")); }
   | call                                 { $$ = $1; }
   | ';'                                  { $$ = lua_stmt (""); }
   ;

elseopt:
     %empty                               { $$ = NULL; }
   | "else" statlist                      { $$ = lua_block ($2); }
   ;

opt_init:
     %empty                               { $$ = NULL; }
   | '=' explist                          { $$ = lua_join ($2, ", "); }
   ;

forstep:
     %empty                               { $$ = NULL; }
   | ',' expr                             { $$ = $2; }
   ;

funcname:
     NAME                                 { $$ = $1; }
   | funcname '.' NAME                    { $$ = lua_field ($1, $3->text); }
   | funcname ':' NAME                    { $$ = lua_make (lua_cat ($1->text, ":", $3->text, NULL), LUA_PREC_ATOM); }
   ;

parlist:
     %empty                               { $$ = lua_atom (lua_dup ("")); }
   | namelist                             { $$ = lua_join ($1, ", "); }
   | namelist ',' "..."                  { $$ = lua_make (lua_cat (lua_join ($1, ", ")->text, ", ...", NULL), LUA_PREC_ATOM); }
   | "..."                               { $$ = lua_atom (lua_dup ("...")); }
   ;

explist:
     expr                                 { $$ = fmt_list_new ($1); }
   | explist ',' expr                     { $$ = fmt_list_append ($1, $3); }
   ;

namelist:
     NAME                                 { $$ = fmt_list_new ($1); }
   | namelist ',' NAME                    { $$ = fmt_list_append ($1, $3); }
   ;

varlist:
     var                                  { $$ = fmt_list_new ($1); }
   | varlist ',' var                      { $$ = fmt_list_append ($1, $3); }
   ;

fieldlist:
     field                                { $$ = fmt_list_new ($1); }
   | fieldlist ',' field                  { $$ = fmt_list_append ($1, $3); }
   | fieldlist ';' field                  { $$ = fmt_list_append ($1, $3); }
   ;

args:
     '(' ')'                              { $$ = lua_atom (lua_dup ("()")); }
   | '(' explist ')'                      { $$ = lua_make (lua_cat ("(", lua_join ($2, ", ")->text, ")", NULL), LUA_PREC_ATOM); }
   | tableconstructor                     { $$ = $1; }
   | STRING                               { $$ = $1; }
   ;

call:
     prefixexp args                       { $$ = lua_call ($1, $2); }
   | prefixexp ':' NAME args              { $$ = lua_method_call ($1, $3->text, $4); }
   ;

prefixexp:
     var                                  { $$ = $1; }
   | '(' expr ')'                         { $$ = lua_group ($2); }
   ;

var:
     NAME                                 { $$ = $1; }
   | var '[' expr ']'                     { $$ = lua_index ($1, $3); }
   | var '.' NAME                         { $$ = lua_field ($1, $3->text); }
   ;

tableconstructor:
     '{' '}'                              { $$ = lua_atom (lua_dup ("{}")); }
   | '{' fieldlist optfieldsep '}'        { $$ = lua_table ($2); }
   ;

optfieldsep:
     %empty                               { $$ = NULL; }
   | ','                                  { $$ = NULL; }
   | ';'                                  { $$ = NULL; }
   ;

field:
     '[' expr ']' '=' expr                { $$ = lua_make (lua_cat ("[", $2->text, "] = ", $5->text, NULL), LUA_PREC_ATOM); }
   | NAME '=' expr                        { $$ = lua_make (lua_cat ($1->text, " = ", $3->text, NULL), LUA_PREC_ATOM); }
   | expr                                 { $$ = $1; }
   ;

expr:
     expr "or" exprand                   { $$ = lua_bin ($1, " or ", $3, LUA_PREC_OR, 0); }
   | exprand                              { $$ = $1; }
   ;

exprand:
     exprand "and" exprcmp               { $$ = lua_bin ($1, " and ", $3, LUA_PREC_AND, 0); }
   | exprcmp                              { $$ = $1; }
   ;

exprcmp:
     exprcmp "==" exprconcat             { $$ = lua_bin ($1, " == ", $3, LUA_PREC_CMP, 0); }
   | exprcmp "~=" exprconcat              { $$ = lua_bin ($1, " ~= ", $3, LUA_PREC_CMP, 0); }
   | exprcmp "<" exprconcat               { $$ = lua_bin ($1, " < ", $3, LUA_PREC_CMP, 0); }
   | exprcmp "<=" exprconcat              { $$ = lua_bin ($1, " <= ", $3, LUA_PREC_CMP, 0); }
   | exprcmp ">" exprconcat               { $$ = lua_bin ($1, " > ", $3, LUA_PREC_CMP, 0); }
   | exprcmp ">=" exprconcat              { $$ = lua_bin ($1, " >= ", $3, LUA_PREC_CMP, 0); }
   | exprconcat                           { $$ = $1; }
   ;

exprconcat:
     exprconcat ".." expradd              { $$ = lua_bin ($1, " .. ", $3, LUA_PREC_CONCAT, 1); }
   | expradd                              { $$ = $1; }
   ;

expradd:
     expradd '+' exprmul                  { $$ = lua_bin ($1, " + ", $3, LUA_PREC_ADD, 0); }
   | expradd '-' exprmul                  { $$ = lua_bin ($1, " - ", $3, LUA_PREC_ADD, 0); }
   | exprmul                              { $$ = $1; }
   ;

exprmul:
     exprmul '*' exprunary                { $$ = lua_bin ($1, " * ", $3, LUA_PREC_MUL, 0); }
   | exprmul '/' exprunary                { $$ = lua_bin ($1, " / ", $3, LUA_PREC_MUL, 0); }
   | exprmul '%' exprunary                { $$ = lua_bin ($1, " % ", $3, LUA_PREC_MUL, 0); }
   | exprunary                            { $$ = $1; }
   ;

exprunary:
     '-' exprunary                        { $$ = lua_unary ("-", $2, LUA_PREC_UNARY); }
   | "not" exprunary                      { $$ = lua_unary ("not ", $2, LUA_PREC_UNARY); }
   | '#' exprunary                        { $$ = lua_unary ("#", $2, LUA_PREC_UNARY); }
   | exprpow                              { $$ = $1; }
   ;

exprpow:
     exprprimary '^' exprpow              { $$ = lua_bin ($1, " ^ ", $3, LUA_PREC_POW, 1); }
   | exprprimary                          { $$ = $1; }
   ;

exprprimary:
     NUMBER                               { $$ = $1; }
   | STRING                               { $$ = $1; }
   | "nil"                                { $$ = lua_atom (lua_dup ("nil")); }
   | "true"                               { $$ = lua_atom (lua_dup ("true")); }
   | "false"                              { $$ = lua_atom (lua_dup ("false")); }
   | "..."                                { $$ = lua_atom (lua_dup ("...")); }
   | call                                 { $$ = $1; }
   | tableconstructor                     { $$ = $1; }
   | functionexpr                         { $$ = $1; }
   | prefixexp                            { $$ = $1; }
   ;

functionexpr:
     "function" '(' parlist ')' statlist "end"
                                         { $$ = lua_function (lua_dup (""), $3, lua_block ($5), 0); }
   ;

NAME:
     /[A-Za-z_][A-Za-z0-9_]*/              { $$ = lua_atom (lua_dup ($TOKEN)); }
   ;

STRING:
     /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/     { $$ = lua_atom (lua_dup ($TOKEN)); }
   ;

NUMBER:
     /0[xX][0-9A-Fa-f]+(\.[0-9A-Fa-f]+)?[pP][+-]?[0-9]+|[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/
                                         { $$ = lua_atom (lua_dup ($TOKEN)); }
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
