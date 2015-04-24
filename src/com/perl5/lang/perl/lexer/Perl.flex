package com.perl5.lang.perl.lexer;

/*
    http://jflex.de/manual.html
    http://www2.cs.tum.edu/projects/cup

*/

import com.intellij.lexer.FlexLexer;
import com.intellij.psi.TokenType;
import com.intellij.psi.tree.IElementType;
import org.jetbrains.annotations.NotNull;
import com.perl5.lang.perl.lexer.helpers.PerlFunction;
import com.perl5.lang.perl.lexer.helpers.PerlScalar;
import com.perl5.lang.perl.lexer.helpers.PerlHash;
import com.perl5.lang.perl.lexer.helpers.PerlGlob;
import com.perl5.lang.perl.lexer.helpers.PerlArray;
import com.perl5.lang.perl.lexer.helpers.PerlPackage;

%%

%class PerlLexer
%extends PerlLexerProto
%implements FlexLexer, PerlTokenTypes
%unicode
%public

%function advance
%type IElementType

//%line
//%column
%{
    public void setTokenStart(int position){zzCurrentPos = zzStartRead = position;}
    public int getNextTokenStart(){ return zzMarkedPos;}
    public boolean isLastToken(){ return zzMarkedPos == zzEndRead; }

    public void yybegin_LEX_MULTILINE(){yybegin(LEX_MULTILINE);}
    public void yybegin_YYINITIAL(){yybegin(YYINITIAL);}
    public void yybegin_LEX_MULTILINE_TOKEN(){yybegin(LEX_MULTILINE_TOKEN);}

	protected int dataBlockStart = 0;

	protected void StartDataBlock()
	{
		dataBlockStart = zzStartRead;
        yybegin(LEX_EOF);
	}

	protected int podBlockStart = 0;

	protected void StartPodBlock()
	{
		podBlockStart = zzStartRead;
        yybegin(LEX_POD);
	}
%}


/*
// Char classes
*/
NEW_LINE = \r?\n
WHITE_SPACE     = [ \t\f]
CHAR_SEMI       = ;
//CHAR_ANY        = .
ALFANUM         = [a-zA-Z0-9_]
FUNCTION_NAME   = [a-zA-Z_]{ALFANUM}+
THE_END         = __END__
THE_DATA         = __DATA__
LINE            = .*
FULL_LINE       = .*{NEW_LINE}?

DQ_STRING        = \"[^\"\n\r]*\"
SQ_STRING        = \'[^\'\n\r]*\'

MULTILINE_MARKER = [^\"\'\s\n\r]+
MULTILINE_MARKER_SQ = "<<"{WHITE_SPACE}*\'{MULTILINE_MARKER}\'
MULTILINE_MARKER_DQ = "<<"{WHITE_SPACE}*\"{MULTILINE_MARKER}\"

POD_OPEN         = \=(pod|head1|head2|head3|head4|over|item|back|begin|end|for|encoding){FULL_LINE}
POD_CLOSE       = \="cut"{FULL_LINE}

DEPACKAGE = "::"

PACKAGE_NAME = {ALFANUM}+ ({DEPACKAGE}{ALFANUM}+)*

PACKAGE_STATIC_CALL = ({ALFANUM}+{DEPACKAGE})+
PACKAGE_INSTANCE_CALL = {ALFANUM}+ ({DEPACKAGE}{ALFANUM}+)* "->"

FUNCTION_NAME = {ALFANUM}+
VAR_SCALAR = [$][$]*{ALFANUM}+
VAR_ARRAY = [@][$]*{ALFANUM}+
VAR_HASH = [%][$]*{ALFANUM}+
VAR_GLOB = [*][$]*{ALFANUM}+
NUMBER = "-"?[0-9_]+(\.[0-9_]+)?

END_OF_LINE_COMMENT = "#" {FULL_LINE}

//%state STRING
//%state YYINITIAL
%state PACKAGE_DEFINITION
%state FUNCTION_DEFINITION
%state PACKAGE_USE
%state LEX_REQUIRE
%state PACKAGE_USE_PARAMS
%state PACKAGE_STATIC_CALL
%state PACKAGE_INSTANCE_CALL
%xstate LEX_EOF, LEX_POD, LEX_MULTILINE, LEX_MULTILINE_TOKEN
%state LEX_DEREFERENCE
%%

<YYINITIAL>{
    {THE_END}               {StartDataBlock(); break;}
    {THE_DATA}               {StartDataBlock(); break;}
    {POD_OPEN}               {StartPodBlock();break;}
}
<LEX_EOF>
{
    {FULL_LINE} {
        if( zzMarkedPos == zzEndRead )
        {
            zzCurrentPos = zzStartRead = dataBlockStart;
            return PERL_COMMENT_BLOCK;
        }
        break;
    }
}
<LEX_POD>
{
    {POD_CLOSE} {
        zzCurrentPos = zzStartRead = podBlockStart;
        yybegin(YYINITIAL);
        return PERL_POD;
    }
    {FULL_LINE} {
        if( zzMarkedPos == zzEndRead )
        {
            zzCurrentPos = zzStartRead = podBlockStart;
            return PERL_POD;
        }
        break;
    }
}

{MULTILINE_MARKER_SQ}   {prepareForMultiline(PERL_SQ_STRING);return PERL_MULTILINE_MARKER;}
{MULTILINE_MARKER_DQ}   {prepareForMultiline(PERL_DQ_STRING);return PERL_MULTILINE_MARKER;}

{NEW_LINE}   {
    if( isWaitingMultiLine() ) // this could be done using lexical state, like prepared or smth
    {
        startMultiLine();
    }
    return PERL_NEWLINE;
}

<LEX_MULTILINE>{
    {LINE}  {
        if( isMultilineEnd() || isLastToken())
        {
            return endMultiline();
        }
        break;
    }
    {NEW_LINE}  {
        if( isLastToken() )
        {
            return endMultiline();
        }
        break;
    }
}
<LEX_MULTILINE_TOKEN>{
    .*  {yybegin(YYINITIAL);return PERL_MULTILINE_MARKER;}
}


{END_OF_LINE_COMMENT}  { return PERL_COMMENT; }
{CHAR_SEMI}     {
//    if( !isWaitingMultiLine() )
        yybegin(YYINITIAL);
    return PERL_SEMI;
}
{WHITE_SPACE}+   {return TokenType.WHITE_SPACE;}
"{"             {return PERL_LBRACE;}
"}"             {return PERL_RBRACE;}
"["             {return PERL_LBRACK;}
"]"             {return PERL_RBRACK;}
"("             {return PERL_LPAREN;}
")"             {return PERL_RPAREN;}
","			    {return PERL_COMMA;}
"=>"			{return PERL_COMMA;}
"->"			{yybegin(LEX_DEREFERENCE);return PERL_DEREFERENCE;}
{DEPACKAGE}		{return PERL_DEPACKAGE;}
{DQ_STRING}     {return PERL_DQ_STRING;}
{SQ_STRING}     {return PERL_SQ_STRING;}
{NUMBER}        {return PERL_NUMBER;}

///////////////////////////////// PERL VARIABLE ////////////////////////////////////////////////////////////////////////
{VAR_SCALAR} {return PerlScalar.getScalarType(yytext().toString());}
{VAR_HASH} {return PerlHash.getHashType(yytext().toString());}
{VAR_ARRAY} {return PerlArray.getArrayType(yytext().toString());}
{VAR_GLOB} {return PerlGlob.getGlobType(yytext().toString());}

<PACKAGE_USE_PARAMS>
{
    {ALFANUM}+  {return PERL_SQ_STRING;}
}

<PACKAGE_USE>{
    {PACKAGE_NAME}    {
        yybegin(PACKAGE_USE_PARAMS);
        return PerlPackage.getPackageType(yytext().toString()); // @todo wtf it's not being resolved without package?
    }
}

<PACKAGE_DEFINITION>{
    {PACKAGE_NAME}    {return PERL_PACKAGE;}
}

<FUNCTION_DEFINITION>{
    {FUNCTION_NAME}    {yybegin(YYINITIAL);return PERL_FUNCTION;}
}

<PACKAGE_STATIC_CALL>
{
    {ALFANUM}+ {return PERL_STATIC_METHOD_CALL;}
}

{PACKAGE_STATIC_CALL} {
    yybegin(PACKAGE_STATIC_CALL);
    yypushback(2);
    return PERL_PACKAGE;
}

<PACKAGE_INSTANCE_CALL>
{
    {ALFANUM}+ {return PERL_INSTANCE_METHOD_CALL;}
}

{PACKAGE_INSTANCE_CALL} {
    yybegin(PACKAGE_INSTANCE_CALL);
    yypushback(2);
    return PERL_PACKAGE;
}

<LEX_REQUIRE>{
    {PACKAGE_NAME}    {return PERL_PACKAGE;}
}

<YYINITIAL> {
  /* whitespace */
    "use"			{yybegin(PACKAGE_USE);return PerlFunction.getFunctionType(yytext().toString());}
    "no"			{yybegin(PACKAGE_USE); return PerlFunction.getFunctionType(yytext().toString());}

    "sub"			{yybegin(FUNCTION_DEFINITION); return PerlFunction.getFunctionType(yytext().toString());}
    "package"       {yybegin(PACKAGE_DEFINITION); return PerlFunction.getFunctionType(yytext().toString());}
    "require"       {yybegin(LEX_REQUIRE);return PerlFunction.getFunctionType(yytext().toString());}
}

"++"			{return PERL_OPERATOR;}
"--"			{return PERL_OPERATOR;}
"**"			{return PERL_OPERATOR;}
"!"			{return PERL_OPERATOR;}
"~"			{return PERL_OPERATOR;}
"\\"			{return PERL_OPERATOR;}
"+"			{return PERL_OPERATOR;}
"-"			{return PERL_OPERATOR;}
"=~"			{return PERL_OPERATOR;}
"!~"			{return PERL_OPERATOR;}
"*"			{return PERL_OPERATOR;}
"/"			{return PERL_OPERATOR;}
"%"			{return PERL_OPERATOR;}
"x"			{return PERL_OPERATOR;}
"<<"			{return PERL_OPERATOR;}
">>"			{return PERL_OPERATOR;}
"<"			{return PERL_OPERATOR;}
">"			{return PERL_OPERATOR;}
"<="			{return PERL_OPERATOR;}
">="			{return PERL_OPERATOR;}
"lt"			{return PERL_OPERATOR;}
"gt"			{return PERL_OPERATOR;}
"le"			{return PERL_OPERATOR;}
"ge"			{return PERL_OPERATOR;}
"=="			{return PERL_OPERATOR;}
"!="			{return PERL_OPERATOR;}
"<=>"			{return PERL_OPERATOR;}
"eq"			{return PERL_OPERATOR;}
"ne"			{return PERL_OPERATOR;}
"cmp"			{return PERL_OPERATOR;}
"~~"			{return PERL_OPERATOR;}
"&"			{return PERL_OPERATOR;}
"|"			{return PERL_OPERATOR;}
"^"			{return PERL_OPERATOR;}
"&&"			{return PERL_OPERATOR;}
"||"			{return PERL_OPERATOR;}
"//"			{return PERL_OPERATOR;}
".."			{return PERL_OPERATOR;}
"..."			{return PERL_OPERATOR;}
"?"			{return PERL_OPERATOR;}
":"			{return PERL_OPERATOR;}
"="			{return PERL_OPERATOR;}
"+="			{return PERL_OPERATOR;}
"-="			{return PERL_OPERATOR;}
"*="			{return PERL_OPERATOR;}
"not"			{return PERL_OPERATOR;}
"and"			{return PERL_OPERATOR;}
"or"			{return PERL_OPERATOR;}
"xor"			{return PERL_OPERATOR;}

{FUNCTION_NAME} { return PerlFunction.getFunctionType(yytext().toString());}

/* error fallback */
[^]    { return PERL_BAD_CHARACTER; }