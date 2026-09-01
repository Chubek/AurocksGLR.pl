# AurocksGLR Grammar for JSON -- Minimal
# A scannerless GLR grammar. Whitespace handling is assumed to be
# declared via %skip (see the %skip directive below).

%{

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* A simple singly linked list used for arrays and object members. */
typedef struct SList
{
   struct YY_TYPE *value;   /* element (array) or member value (object) */
   char           *key;     /* member key, NULL for array elements      */
   struct SList   *next;
} SList;

typedef struct YY_TYPE
{
   enum YY_TAG
   {
      JSON_STRING,
      JSON_NUMBER,
      JSON_ARRAY,
      JSON_OBJECT,
      JSON_TRUE,
      JSON_FALSE,
      JSON_NULL,
   } tag;

   union
   {
      char         *string;
      double        number;
      SList        *array;    /* JSON_ARRAY  */
      SList        *object;   /* JSON_OBJECT: list of keyed members */
   } as;
} YY_TYPE;

/* Constructors -- one per shape of node. */
static YY_TYPE *build_string (char *s);
static YY_TYPE *build_number (double d);
static YY_TYPE *build_array  (SList *elems);
static YY_TYPE *build_object (SList *members);
static YY_TYPE *build_lit    (enum YY_TAG tag);   /* true / false / null */

/* List helpers. append() adds to the tail so source order is preserved. */
static SList *slist_new    (char *key, YY_TYPE *value);
static SList *slist_append (SList *list, char *key, YY_TYPE *value);

%}

%target C
%start json

%skip /[ \t\r\n]+/          /* scannerless: skip insignificant whitespace */

%%

json:
     %empty                 { $$ = NULL; }
   | value                  { $$ = $1;   }
   ;

value:
     object                 { $$ = $1; }
   | array                  { $$ = $1; }
   | STRING                 { $$ = build_string ($1); }
   | NUMBER                 { $$ = build_number ($1); }
   | "true"                 { $$ = build_lit (JSON_TRUE);  }
   | "false"                { $$ = build_lit (JSON_FALSE); }
   | "null"                 { $$ = build_lit (JSON_NULL);  }
   ;

// utf8 characters in single quotes, utf8 strings in double quotes
// regular expressions between forward slashes
object:
     '{' '}'                            { $$ = build_object (NULL); }
   | '{' members '}'                    { $$ = build_object ($2);   }
   ;

members:
     member                             { $$ = $1; }
   | members ',' member                 { $$ = slist_append ($1, $3->key, $3->value); }
   ;

member:
     STRING ':' value                   { $$ = slist_new ($1, $3); }
   ;

array:
     '[' ']'                            { $$ = build_array (NULL); }
   | '[' elements ']'                   { $$ = build_array ($2);   }
   ;

elements:
     value                              { $$ = slist_new (NULL, $1); }
   | elements ',' value                 { $$ = slist_append ($1, NULL, $3); }
   ;

STRING:
     /"([^"\\]|\\["\\\/bfnrt]|\\u[0-9a-fA-F]{4})*"/
                                        { $$ = my_strdup ($TOKEN); }
   ;

NUMBER:
     /-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/
                                        { $$ = strtod ($TOKEN, NULL); }
   ;

%%

/* --- Constructors --- */

static YY_TYPE *
build_string (char *s)
{
   YY_TYPE *n = malloc (sizeof *n);
   n->tag = JSON_STRING;
   n->as.string = s;
   return n;
}

static YY_TYPE *
build_number (double d)
{
   YY_TYPE *n = malloc (sizeof *n);
   n->tag = JSON_NUMBER;
   n->as.number = d;
   return n;
}

static YY_TYPE *
build_array (SList *elems)
{
   YY_TYPE *n = malloc (sizeof *n);
   n->tag = JSON_ARRAY;
   n->as.array = elems;
   return n;
}

static YY_TYPE *
build_object (SList *members)
{
   YY_TYPE *n = malloc (sizeof *n);
   n->tag = JSON_OBJECT;
   n->as.object = members;
   return n;
}

static YY_TYPE *
build_lit (enum YY_TAG tag)
{
   YY_TYPE *n = malloc (sizeof *n);
   n->tag = tag;
   return n;
}

/* --- List helpers --- */

static SList *
slist_new (char *key, YY_TYPE *value)
{
   SList *node = malloc (sizeof *node);
   node->key   = key;
   node->value = value;
   node->next  = NULL;
   return node;
}

static SList *
slist_append (SList *list, char *key, YY_TYPE *value)
{
   SList *node = slist_new (key, value);
   if (list == NULL)
      return node;
   SList *tail = list;
   while (tail->next != NULL)
      tail = tail->next;
   tail->next = node;
   return list;
}

