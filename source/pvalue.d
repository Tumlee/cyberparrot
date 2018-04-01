module cyberparrot.pvalue;

import std.ascii;
import std.conv;

class PValue
{
    string value = null;
    PValue[] elements;
    
    this(string v = null)
    {
        value = v;
    }

    bool isValue() const
    {
        return (value !is null);
    }
    
    bool isList() const
    {
        return (value is null);
    }
    
    string express()
    {
        if(isValue())
            return value;
    
        string expression;
    
        foreach(i; 0 .. elements.length)
        {
            if(elements[i].isValue)
                expression ~= elements[i].express();
            
            else
                expression ~= "(" ~  elements[i].express() ~ ")";
                
            if(i != elements.length - 1)
                expression ~= " ";
        }
        
        return expression;
    }
    
    ulong numElements() const
    {
        return elements.length;
    }
}

//This function returns true if the parenthesis are balanced in the string.
bool checkParenthesis(string expression)
{
    int depth = 0;
    
    foreach(c; expression)
    {
        if(c == '(')
            depth++;
            
        if(c == ')')
        {
            if(depth-- == 0)
                return false;
        }
    }
    
    return depth == 0;
}

//Returns true if the expression is 'wrapped' in parenthesis.
bool inParenthesis(string expression)
{
    if(expression.length < 2)
        return false;
        
    return (expression[0] == '(') && (expression[$ - 1] == ')');
}

//Splits the string into seperate "tokens" while being aware of parenthesis.
string[] splitTokens(string expression)
{
    //Empty sets are allowed in this file format.
    if(expression.length == 0)
        return [];
        
    int depth = 0;
    string[] tokens;
    string currentToken;

    //We add a space at the end of the input string to force the parser
    //to add the last token to the list.    
    foreach(c; expression ~ " ")
    {
        if(c == '(')
            depth++;
            
        if(c == ')')
            depth--;
        
        //If we've found a whitespace or an end parenthesis
        //at the current depth level our current token ends.
        if(depth == 0 && c.isWhite)
        {
            //There should be no empty tokens.
            if(currentToken.length != 0)
            {
                tokens ~= currentToken;
                currentToken = "";
            } 
        }
        else
        {
            currentToken ~= c;
        }
    }
    
    return tokens;
}

PValue parsePValue(string expression)
{
    if(checkParenthesis(expression) == false)
        throw new Exception("Parenthesis are not balanced in this expression");

    //Split the string by whitespace, being mindful of parenthesis
    string[] tokens = splitTokens(expression);
    
    auto pv = new PValue();
    
    foreach(token; tokens)
    {
        //Any items contained in parenthesis are considered their own list.
        if(token.inParenthesis)
            pv.elements ~= parsePValue(token[1 .. $ - 1]);
        
        //Anything else is considered a string "value".
        else
            pv.elements ~= new PValue(token);
    }
        
    return pv;
}

void validateNumElements(const PValue pv, int minimum, string expectedType)
{
    if(pv.numElements < minimum)
    {
        string error = "Expected " ~ minimum.to!string ~ " elements in type " ~
                        expectedType ~ ", got " ~ pv.numElements.to!string;
        throw new Exception(error);
    }
}

void validatePVType(const PValue pv, ulong index, bool match, string expectedType)
{
    if(pv.elements[index].isValue() != match)
    {
        string expected = match == true ? "string" : "list";
        string error = "Expected element " ~ index.to!string ~ " to be a " ~
                        expected ~ " in type " ~ expectedType;
        throw new Exception(error);
    }
}

T extractElement(T)(const PValue pv, ulong index)
{
    try
    {
        return pv.elements[index].value.to!T;
    }
    catch(std.conv.ConvException)
    {
        throw new Exception("Expected element " ~ (index + 1).to!string ~
                            " to be of type " ~ typeid(T).to!string);
    }
}

