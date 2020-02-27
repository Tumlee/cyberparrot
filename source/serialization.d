module cyberparrot.serialization;
public import std.json;
import std.traits;
import std.conv;
import std.stdio;
import std.file;

static struct DataMember { string name = null; bool required = false; bool debugField = false; }
enum DataContract;

interface Serializable
{
}

T deserialize(T:Serializable)(JSONValue jv)
{
    if(jv.type == JSONType.null_)
        return null;

    if(jv.type != JSONType.object)
        throw new Exception("Can only call deserialize on json objects");
    
    T obj = new T;

    string dmName;
    string fieldName;
    string actualFieldName;

    //Check for any fields with the @DataMember attribute
    static foreach(field; getSymbolsByUDA!(T, DataMember))
    {
        //Grab the 'name' field from the DataMember attribute.
        dmName = getUDAs!(field, DataMember)[0].name;

        //Look for that field in the JSON. If the DataMember doesn't define a name, use the actual field name by default.
        actualFieldName = field.stringof; 
        fieldName = dmName != null ? dmName : actualFieldName;

        if(getUDAs!(field, DataMember)[0].debugField)
            writeln("Parsing: " ~ fieldName);

        if(fieldName in jv)
        {
            //FIXME: Still need to handle arrays
            JSONValue jsonField = jv[fieldName];
            __traits(getMember, obj, field.stringof) = deserialize!(typeof(field))(jsonField);
        }
        else
        {
            if(getUDAs!(field, DataMember)[0].required == true)
                throw new Exception("Missing required field: " ~ fieldName);
            
            if(getUDAs!(field, DataMember)[0].debugField)
                writeln("Field not found: " ~ fieldName);
        }
    }

    return obj;
}

//Deserialization for basic types, arrays, and associative arrays.
T deserialize(T:long)(JSONValue jv)
{
    if(jv.type != JSONType.integer)
        throw new Exception("Expected integer type.");

    long extractedValue = jv.integer;

    if(extractedValue > T.max || extractedValue < T.min)
        throw new Exception("Field out of range");

    return cast(T) jv.integer;
}

T deserialize(T:string)(JSONValue jv)
{
    if(jv.type == JSONType.null_)
        return null;
    
    if(jv.type != JSONType.string)
        throw new Exception("Expected string type");

    return jv.str;
}

T deserialize(T:bool)(JSONValue jv)
{
    if(jv.type == JSONType.true_)
        return true;

    if(jv.type == JSONType.false_)
        return false;

    throw new Exception("Expected boolean type");
}

T deserialize(T:double)(JSONValue jv)
{
    //FIXME: This should be handled by nullable types instead.
    if(jv.type == JSONType.null_)
        return T.nan;
    
    if(jv.type != JSONType.float_)
        throw new Exception("Expected float type.");

    return jv.floating;
}

T deserialize(T)(JSONValue jv) if(isArray!T)
{
    if(jv.type != JSONType.array)
        throw new Exception("Expected an array type");

    T array;

    foreach(element; jv.array)
        array ~= deserialize!(typeof(array[0]))(element);

    return array;
}

T deserialize(T)(JSONValue jv) if(isAssociativeArray!T && is(KeyType!T == string))
{
    if(jv.type != JSONType.object)
        throw new Exception("Expected an object type");

    T aa;

    foreach(key; jv.object.keys)
        aa[key] = deserialize!(ValueType!T)(jv.object[key]);

    return aa;
}

//Serialization for basic types, arrays, and associative arrays.
JSONValue serialize(T:long)(T value)
{
    return JSONValue(value);
}

JSONValue serialize(T:string)(T value)
{
    return JSONValue(value);
}

JSONValue serialize(T:bool)(T value)
{
    return JSONValue(value);
}

JSONValue serialize(T:double)(T value)
{
    return JSONValue(value);
}

JSONValue serialize(T)(T array) if(isArray!T)
{
    JSONValue jva;
    jva.array = [];

    foreach(element; array)
        jva.array ~= serialize!(typeof(array[0]))(element);

    return jva;
}

JSONValue serialize(T)(T aa) if(isAssociativeArray!T && is(KeyType!T == string))
{
    if(aa is null)
        return JSONValue(null);
    
    JSONValue jv;

    foreach(key; aa.keys)
        jv[key] = serialize!(ValueType!T)(aa[key]);

    return jv;
}

JSONValue serialize(T:Serializable)(T obj)
{
    if(obj is null)
        return JSONValue(null);
    
    JSONValue jv;

    string dmName;
    string fieldName;
    string actualFieldName;

    //Check for any fields with the @DataMember attribute
    static foreach(field; getSymbolsByUDA!(T, DataMember))
    {
        //Grab the 'name' field from the DataMember attribute.
        dmName = getUDAs!(field, DataMember)[0].name;

        //Look for that field in the JSON. If the DataMember doesn't define a name, use the actual field name by default.
        actualFieldName = field.stringof; 
        fieldName = dmName != null ? dmName : actualFieldName;

        jv[fieldName] = serialize!(typeof(field))(__traits(getMember, obj, field.stringof));
    }

    return jv;
}

void saveToJsonFile(T:Serializable)(T obj, string filePath)
{
    string jsonText = obj.serialize().toPrettyString();
    std.file.write(filePath, jsonText);
}

T loadFromJsonFile(T:Serializable)(string filePath)
{
    File file = File(filePath, "r");
    string jsonText = readText(filePath);
    JSONValue jv = parseJSON(jsonText);
    return deserialize!T(jv);
}