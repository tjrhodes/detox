/****
* Copyright (c) 2012 Jason O'Neil
* 
* Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
* 
****/

package dtx.widget;

import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Format;
import tink.macro.tools.MacroTools;
using tink.macro.tools.MacroTools;
using StringTools;
using Lambda;
using Detox;

#if macro 
class BuildTools 
{
	static var fieldsForClass:Hash<Array<Field>> = new Hash();

	/** Allow us to get a list of fields, but will keep a local copy, in case we make changes.  This way 
	in an autobuild macro you can use BuildTools.getFields() over and over, and modify the array each time,
	and finally use it as the return value of the build macro.  */
	public static function getFields():Array<Field>
	{
        var className = haxe.macro.Context.getLocalClass().toString();
        if (fieldsForClass.exists(className) == false)
        {
        	fieldsForClass.set(className, haxe.macro.Context.getBuildFields());
        }
        return fieldsForClass.get(className);
	}

	/** Searches the metadata for the current class - expects to find a single string @dataName("my string"), otherwise throws an error. */
	public static function getClassMetadata_String(dataName:String)
	{
        var p = Context.currentPos();                           // Position where the original Widget class is declared
        var localClass = haxe.macro.Context.getLocalClass();    // Class that is being declared
        var meta = localClass.get().meta;                       // Metadata of the this class
        var result = null;
		if (meta.has(dataName))
        {
            for (metadataItem in meta.get())
            {
                if (metadataItem.name == dataName)
                {
                    if (metadataItem.params.length == 0) Context.error("Metadata " + dataName + "() exists, but was empty.", p);
                    for (targetMetaData in metadataItem.params)
                    {
                        switch( targetMetaData.expr ) 
                        {
                            case EConst(c):
                                switch(c) 
                                {
                                    case CString(str): 
                                        result = str;
                                        break;
                                    default: 
                                        Context.error("Metadata for " + dataName + "() existed, but was not a constant String.", p);
                                }
                            default: 
                                Context.error("Metadata for " + dataName + "() existed, but was not a constant value.", p);
                        } 
                    }
                }
            }
        }
        return result;
	}

	/** Takes a field declaration, and if it doesn't exist, adds it.  If it does exist, it returns the 
	existing one. */
    public static function getOrCreateField(fieldToAdd:Field)
    {
        var p = Context.currentPos();                           // Position where the original Widget class is declared
        var localClass = haxe.macro.Context.getLocalClass();    // Class that is being declared
        var fields = getFields();
        var field:Field;

        if (fields.exists(function (f) { return f.name == fieldToAdd.name; }))
        {
            // If it does exist, get it
            return fields.filter(function (f) { return f.name == fieldToAdd.name; }).first();
        }
        else
        {
            // If it doesn't exist, create it
            fields.push(fieldToAdd);
            return fieldToAdd;
        }
    }

    /** Creates a new property on the class, with the given name and type.  Optionally can set a setter or 
    a getter.  Returns a simple object containing the fields for the property, the setter and the getter. */
    public static function getOrCreateProperty(propertyName:String, propertyType:haxe.macro.ComplexType, useGetter:Bool, useSetter:Bool):{ property:Field, getter:Field, setter:Field }
    {
        var p = Context.currentPos();                           // Position where the original Widget class is declared
        
        var getterString = (useGetter) ? "get_" + propertyName : "default";
        var setterString = (useSetter) ? "set_" + propertyName : "default";
        var variableRef = propertyName.resolve();

        // Set up the property
        var property = getOrCreateField({
            pos: p,
            name: propertyName,
            meta: [],
            kind: FieldType.FProp(getterString, setterString, propertyType),
            doc: "Field referencing the " + propertyName + " partial in this widget.",
            access: [APublic]
        });

        // Set up the getter
        var getter = null;
        if (useGetter)
        {
            var getterBody = macro {
                // Just return the current value... If they want to add lines to this function later then they can.
                return $variableRef; 
            };
            getter = getOrCreateField({
                pos: p,
                name: getterString,
                meta: [],
                kind: FieldType.FFun({
                        ret: propertyType,
                        params: [],
                        expr: getterBody,
                        args: []
                    }),
                doc: "",
                access: []
            });
        }

        // set up the setter
        var setter = null;
        if (useSetter)
        {
            var setterBody = macro {
                $variableRef = v; 
                return v; 
            };
            setter = getOrCreateField({
                pos: p,
                name: setterString,
                meta: [],
                kind: FieldType.FFun({
                        ret: propertyType,
                        params: [],
                        expr: setterBody,
                        args: [{
                            value: null,
                            type: propertyType,
                            opt: false,
                            name: "v"
                        }]
                    }),
                doc: "",
                access: []
            });
        }

        return {
            property: property,
            getter: getter,
            setter: setter
        }
    }

    /** Add some lines of code to the beginning or end of a function body.  It takes a field (that is a function) as
    the first argument, and an expression as the second.  For now, Haxe expects a block to be passed, and then it will
    go over each line in the block and add them to the function.  Finally you can choose to optionally prepend them, so
    they go at the start of the function, not the end.

    Sample usage:
    var myFn = BuildTools.getOrCreateField(...);
    var linesToAdd = macro {
		for (i in 0...10)
		{
			trace (i);
		}
    };
    BuildTools.addLinesToFunction(myFn, linesToAdd, true);
    */
    public static function addLinesToFunction(field:Field, lines:Expr, ?isPrepend = false)
    {
        // Get the function from the field, or throw an error
        var fn = null;
        switch( field.kind )
        {
            case FFun(f):
                fn = f;
            default: 
                Context.error("addLinesToFunction was sent a field that is not a function.", Context.currentPos());
        }

        // Get the "block" of the function body
        var body = null;
        switch ( fn.expr.expr )
        {
            case EBlock(b):
                body = b;
            default:
                Context.error("addLinesToFunction was expecting an EBlock as the function body, but got something else.", Context.currentPos());
        }
        
        // Get an array of the lines we want to add...
        var linesArray:Array<Expr> = [];
        switch ( lines.expr )
        {
            case EBlock(b):
                // If it's a block, use each statement in the block
                for (line in b)
                {
                    linesArray.push(line);
                }
            default:
                // Otherwise, include it as a single item
                linesArray.push(lines);
        }

        // Add the lines
        if (isPrepend)
        {
        	linesArray.reverse();
	        for (line in linesArray)
	        {
            	body.unshift(line);
	        }
        }
        else 
        {
	        for (line in linesArray)
	        {
            	body.push(line);
	        }
        }
    }
}
#end