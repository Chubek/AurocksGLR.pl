# AurocksGLR Grammar for ASDL -- AST subset

%{

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

typedef struct ASDLNode ASDLNode;
typedef struct ASDLList ASDLList;

struct ASDLList
{
   ASDLNode *item;
   ASDLList *next;
};

struct ASDLNode
{
   enum ASDLKind
   {
      ASDL_MODULE,
      ASDL_DEFINITION,
      ASDL_SUM,
      ASDL_PRODUCT,
      ASDL_CONSTRUCTOR,
      ASDL_FIELD,
      ASDL_ALIAS
   } tag;

   char    *name;
   char    *text;
   char    *modifier;
   ASDLList *items;
   ASDLList *attrs;
};

static char *asdl_cat (const char *first, ...);
static char *asdl_qualify (char *left, char *right);
static ASDLNode *asdl_node (enum ASDLKind tag, char *name, char *text, char *modifier, ASDLList *items, ASDLList *attrs);
static ASDLNode *asdl_module (char *name, ASDLList *definitions);
static ASDLNode *asdl_definition (char *name, ASDLNode *rhs);
static ASDLNode *asdl_sum (ASDLList *constructors, ASDLList *attrs);
static ASDLNode *asdl_product (ASDLList *fields, ASDLList *attrs);
static ASDLNode *asdl_constructor (char *name, ASDLList *fields);
static ASDLNode *asdl_field (char *type_name, char *name, char *modifier);
static ASDLNode *asdl_alias (char *type_name);
static ASDLList *asdl_list_new (ASDLNode *item);
static ASDLList *asdl_list_append (ASDLList *list, ASDLNode *item);
static void asdl_indent (int depth);
static void asdl_print_node (ASDLNode *node, int depth);
static void asdl_print_list (ASDLList *list, int depth);
static void emit_ast (ASDLNode *root);

static char *
asdl_dup (const char *text)
{
   size_t length = strlen (text);
   char *copy = malloc (length + 1);
   if (copy == NULL)
      return NULL;
   memcpy (copy, text, length + 1);
   return copy;
}

static char *
asdl_cat (const char *first, ...)
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
asdl_qualify (char *left, char *right)
{
   return asdl_cat (left, ".", right, NULL);
}

static ASDLNode *
asdl_node (enum ASDLKind tag, char *name, char *text, char *modifier, ASDLList *items, ASDLList *attrs)
{
   ASDLNode *node = malloc (sizeof *node);
   node->tag = tag;
   node->name = name;
   node->text = text;
   node->modifier = modifier;
   node->items = items;
   node->attrs = attrs;
   return node;
}

static ASDLNode *
asdl_module (char *name, ASDLList *definitions)
{
   return asdl_node (ASDL_MODULE, name, NULL, NULL, definitions, NULL);
}

static ASDLNode *
asdl_definition (char *name, ASDLNode *rhs)
{
   return asdl_node (ASDL_DEFINITION, name, NULL, NULL, asdl_list_new (rhs), NULL);
}

static ASDLNode *
asdl_sum (ASDLList *constructors, ASDLList *attrs)
{
   return asdl_node (ASDL_SUM, NULL, NULL, NULL, constructors, attrs);
}

static ASDLNode *
asdl_product (ASDLList *fields, ASDLList *attrs)
{
   return asdl_node (ASDL_PRODUCT, NULL, NULL, NULL, fields, attrs);
}

static ASDLNode *
asdl_constructor (char *name, ASDLList *fields)
{
   return asdl_node (ASDL_CONSTRUCTOR, name, NULL, NULL, fields, NULL);
}

static ASDLNode *
asdl_field (char *type_name, char *name, char *modifier)
{
   return asdl_node (ASDL_FIELD, name, type_name, modifier, NULL, NULL);
}

static ASDLNode *
asdl_alias (char *type_name)
{
   return asdl_node (ASDL_ALIAS, NULL, type_name, NULL, NULL, NULL);
}

static ASDLList *
asdl_list_new (ASDLNode *item)
{
   ASDLList *node = malloc (sizeof *node);
   node->item = item;
   node->next = NULL;
   return node;
}

static ASDLList *
asdl_list_append (ASDLList *list, ASDLNode *item)
{
   ASDLList *node = asdl_list_new (item);
   if (list == NULL)
      return node;

   ASDLList *tail = list;
   while (tail->next != NULL)
      tail = tail->next;
   tail->next = node;
   return list;
}

static void
asdl_indent (int depth)
{
   for (int i = 0; i < depth; i++)
      fputs ("  ", stdout);
}

static void
asdl_print_list (ASDLList *list, int depth)
{
   for (ASDLList *scan = list; scan != NULL; scan = scan->next)
   {
      asdl_print_node (scan->item, depth);
      if (scan->next != NULL)
         fputc ('\n', stdout);
   }
}

static void
asdl_print_node (ASDLNode *node, int depth)
{
   if (node == NULL)
   {
      fputs ("()", stdout);
      return;
   }

   switch (node->tag)
   {
   case ASDL_MODULE:
      asdl_indent (depth);
      printf ("(module %s\n", node->name);
      asdl_print_list (node->items, depth + 1);
      fputc ('\n', stdout);
      asdl_indent (depth);
      fputc (')', stdout);
      break;

   case ASDL_DEFINITION:
      asdl_indent (depth);
      printf ("(definition %s\n", node->name);
      asdl_print_node (node->items ? node->items->item : NULL, depth + 1);
      fputc ('\n', stdout);
      asdl_indent (depth);
      fputc (')', stdout);
      break;

   case ASDL_SUM:
      asdl_indent (depth);
      fputs ("(sum\n", stdout);
      asdl_print_list (node->items, depth + 1);
      if (node->attrs != NULL)
      {
         fputc ('\n', stdout);
         asdl_indent (depth + 1);
         fputs ("(attributes\n", stdout);
         asdl_print_list (node->attrs, depth + 2);
         fputc ('\n', stdout);
         asdl_indent (depth + 1);
         fputc (')', stdout);
      }
      fputc ('\n', stdout);
      asdl_indent (depth);
      fputc (')', stdout);
      break;

   case ASDL_PRODUCT:
      asdl_indent (depth);
      fputs ("(product\n", stdout);
      asdl_print_list (node->items, depth + 1);
      if (node->attrs != NULL)
      {
         fputc ('\n', stdout);
         asdl_indent (depth + 1);
         fputs ("(attributes\n", stdout);
         asdl_print_list (node->attrs, depth + 2);
         fputc ('\n', stdout);
         asdl_indent (depth + 1);
         fputc (')', stdout);
      }
      fputc ('\n', stdout);
      asdl_indent (depth);
      fputc (')', stdout);
      break;

   case ASDL_CONSTRUCTOR:
      asdl_indent (depth);
      printf ("(constructor %s", node->name);
      if (node->items != NULL)
      {
         fputc ('\n', stdout);
         asdl_print_list (node->items, depth + 1);
         fputc ('\n', stdout);
         asdl_indent (depth);
      }
      fputc (')', stdout);
      break;

   case ASDL_FIELD:
      asdl_indent (depth);
      printf ("(field %s", node->text);
      if (node->modifier != NULL)
         printf (" %s", node->modifier);
      if (node->name != NULL)
         printf (" %s", node->name);
      fputc (')', stdout);
      break;

   case ASDL_ALIAS:
      asdl_indent (depth);
      printf ("(alias %s)", node->text);
      break;
   }
}

static void
emit_ast (ASDLNode *root)
{
   asdl_print_node (root, 0);
   fputc ('\n', stdout);
}

%}

%target C
%start module
%skip /[ \t\r\n]+|--[^\n]*/

%%

module:
     "module" NAME '{' definition_list '}'   { $$ = asdl_module ($2, $4); }
   ;

definition_list:
     %empty                                  { $$ = NULL; }
   | definition_list definition              { $$ = asdl_list_append ($1, $2); }
   ;

definition:
     NAME '=' type_rhs                       { $$ = asdl_definition ($1, $3); }
   ;

type_rhs:
     constructor_list attrs_opt              { $$ = asdl_sum ($1, $2); }
   | '(' field_list ')' attrs_opt            { $$ = asdl_product ($2, $4); }
   | NAME                                    { $$ = asdl_alias ($1); }
   ;

constructor_list:
     constructor                             { $$ = asdl_list_new ($1); }
   | constructor_list '|' constructor        { $$ = asdl_list_append ($1, $3); }
   ;

constructor:
     NAME constructor_fields_opt             { $$ = asdl_constructor ($1, $2); }
   ;

constructor_fields_opt:
     %empty                                  { $$ = NULL; }
   | '(' field_list ')'                      { $$ = $2; }
   ;

field_list:
     field                                   { $$ = asdl_list_new ($1); }
   | field_list ',' field                    { $$ = asdl_list_append ($1, $3); }
   ;

field:
     type_name modifier_opt name_opt         { $$ = asdl_field ($1, $3, $2); }
   ;

type_name:
     NAME                                    { $$ = $1; }
   | qualified_name                          { $$ = $1; }
   ;

qualified_name:
     NAME '.' NAME                           { $$ = asdl_qualify ($1, $3); }
   ;

modifier_opt:
     %empty                                  { $$ = NULL; }
   | '?'                                     { $$ = asdl_dup ("?"); }
   | '*'                                     { $$ = asdl_dup ("*"); }
   ;

name_opt:
     %empty                                  { $$ = NULL; }
   | NAME                                    { $$ = $1; }
   ;

attrs_opt:
     %empty                                  { $$ = NULL; }
   | "attributes" '(' field_list ')'         { $$ = $3; }
   ;

NAME:
     /[A-Za-z_][A-Za-z0-9_]*/                 { $$ = asdl_dup ($TOKEN); }
   ;

%%

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

   ASDLNode *root = (ASDLNode *) yyparse (contents);
   free (contents);
   emit_ast (root);
   return 0;
}
