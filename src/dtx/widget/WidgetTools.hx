/****
* Copyright (c) 2013 Jason O'Neil
* 
* Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
* 
****/

package dtx.widget;

import dtx.DOMNode;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Format;
import haxe.macro.Type;
import haxe.macro.Printer;
import haxe.ds.StringMap;
import tink.core.Error;
using haxe.macro.Context;
using tink.MacroApi;
using StringTools;
using Lambda;
using Detox;
using dtx.widget.BuildTools;

class WidgetTools 
{
    static var templates:StringMap<String>;

    /**
    * This macro is called on ANY subclass of detox.widget.Widget
    * 
    * It's purpose is to get the template for each Widget Class
    * It looks for: 
    *  - Metadata in the form: @:template("<div></div>") class MyWidget ...
    *  - Metadata in the form: @:loadTemplate("MyWidgetTemplate.html") class MyWidget ...
    *  - Take a guess at a filename... use current filename, but replace ".hx" with ".html"
    * Once it finds it, it overrides the get_template() method, and makes it return
    * the correct template as a String constant.  So each widget gets its own template
    */
    macro public static function buildWidget():Array<Field>
    {
        if (templates==null) templates = new StringMap();

        var localClass = haxe.macro.Context.getLocalClass();    // Class that is being declared
        var widgetPos = localClass.get().pos;                   // Position where the original Widget class is declared
        var fields = BuildTools.getFields();

        // If get_template() already exists, don't recreate it
        var skipTemplating = BuildTools.hasClassMetadata(":skipTemplating");
        if (!skipTemplating && fields.exists(function (f) return f.name == "get_template") == false)
        {
            // Load the template
            var template = loadTemplate(localClass);

            if (template != null)
            {
                // Process the template looking for partials, variables etc
                // This function processes the template, and returns any binding statements
                // that may be needed for bindings / variables etc.
                
                var result = processTemplate(template);

                // Push the extra class properties that came during our processing
                for (f in result.fields)
                {
                    fields.push(f);
                }

                // Create and add the get_template() field. 
                fields.push(createField_get_template(result.template, template, widgetPos));

                // Keep track of the template in case we need it later...
                templates.set( localClass.toString(), result.template );

                // If @:dtxdebug metadata is found, print the class
                if ( BuildTools.hasClassMetadata(":dtxDebug") )
                {
                    // Add a callback for this class
                    BuildTools.printFields();
                }

                return fields;
            }
        }


        // Leave the fields as is
        return null;
    }

    /**
      * Helper functions
      */

    #if macro

    static function loadTemplate(localClass:Null<haxe.macro.Type.Ref<haxe.macro.Type.ClassType>>):String
    {
        var p = localClass.get().pos;                           // Position where the original Widget class is declared
        var className = localClass.toString();                  // Name of the class eg "my.pack.MyType"
        
        var templateFile:String = "";                           // If we are loading template from a file, this is the filename
        var template:String = "";                               // If the template is directly in metadata, use that.

        // Get the template content if declared in metadata
        var template = BuildTools.getClassMetadata_String(":template", true);
        if (template == null)
        {
            // Check if we are loading a partial from in another template
            var partialInside = BuildTools.getClassMetadata_ArrayOfStrings(":partialInside", true);
            if (partialInside != null && partialInside.length > 0)
            {
                if (partialInside.length == 2)
                {
                    var templateFile = partialInside[0];
                    var partialName = partialInside[1];
                    template = loadPartialFromInTemplate(templateFile, partialName);
                }
                else Context.fatalError('@:partialInside() metadata should be 2 strings: @:partialInside("MyView.html", "_NameOfPartial")', p);
            }

            // Check if a template file is declared in metadata
            if (template == null)
            {
                var templateFile = BuildTools.getClassMetadata_String(":loadTemplate", true);
                if (templateFile == null)
                {
                    // If there is no metadata for the template, look for a file in the same 
                    // spot but with ".html" instead of ".hx" at the end.
                    templateFile = className.replace(".", "/") + ".html";
                }

                // Attempt to load the file
                template = BuildTools.loadFileFromLocalContext(templateFile);
                
                // If still no template, check if @:noTpl() was declared, if not, throw error.
                if (template == null) 
                {
                    var metadata = localClass.get().meta.get();
                    if (!metadata.exists(function(metaItem) return metaItem.name == ":noTpl"))
                    {
                        Context.fatalError('Could not load the widget template: $templateFile', p);
                    }
                }
            }
        }
        return template;
    }

    static function loadPartialFromInTemplate(templateFile:String, partialName:String)
    {
        var p = Context.getLocalClass().get().pos;                       // Position where the original Widget class is declared
        var partialTemplate:String = null;
        
        var fullTemplate = BuildTools.loadFileFromLocalContext(templateFile);
        if (fullTemplate != null) 
        {
            var tpl:DOMCollection = fullTemplate.parse();
            if ( tpl.length==0 )
                Context.fatalError( 'Failed to parse Xml for template file: $templateFile $partialName', p );
            
            var allNodes = Lambda.concat(tpl, tpl.descendants());
            var partialMatches = allNodes.filter(function (n) { return n.nodeType == Xml.Element && n.nodeName == partialName; });
            
            if (partialMatches.length == 1) 
                partialTemplate = partialMatches.first().innerHTML();
            else if (partialMatches.length > 1) 
                Context.fatalError('The partial $partialName was found more than once in the template $templateFile... confusing!', p);
            else 
                Context.fatalError('The partial $partialName was not found in the template $templateFile', p);
        }
        else Context.fatalError('Could not load the file $templateFile that $partialName is supposedly in.', p);

        return partialTemplate;
    }
    
    static function createField_get_template(template:String, original:String, widgetPos:Position):Field
    {
        // Clear whitespace from the start and end of the widget
        var whitespaceStartOrEnd = ~/^\s+|\s+$/g;
        template = whitespaceStartOrEnd.replace(template, "");

        return { 
            name : "get_template", 
            doc : "__Template__:\n\n```\n" + original + "\n```", 
            meta : [], 
            access : [APublic,AOverride], 
            kind : FFun({ 
                args: [], 
                expr: { 
                    expr: EBlock(
                        [
                        { 
                            expr: EReturn(
                                { 
                                    expr: EConst(
                                        CString(template)
                                    ), 
                                    pos: widgetPos
                                }
                            ), 
                            pos: widgetPos
                        }
                        ]
                    ), 
                    pos: widgetPos
                }, 
                params: [], 
                ret: null 
            }), 
            pos: widgetPos
        }
    }

    static var partialNumber:Int; // Used to create name if none given, eg partial_4:DOMCollection
    static var loopNumber:Int; // Used to create name if none given, eg loop_4:Loop
    static function processTemplate(template:String):{ template:String, fields:Array<Field> }
    {
        // Get every node (including descendants)
        var p = Context.currentPos();
        var localClass = Context.getLocalClass();

        var xml = template.parse();
        if ( xml.length==0 ) 
            Context.fatalError( 'Failed to parse template for widget $localClass', Context.getLocalClass().get().pos );
        
        var fieldsToAdd = new Array<Field>();
        partialNumber=0; 
        loopNumber=0; 

        // Process partial declarations on the top level first (and then remove them from the collection/template)
        for ( node in xml ) {
            if (node.isElement() && node.tagName().startsWith('_')) {
                // This is a partial declaration <_MyPartial>template</_MyPartial>
                processPartialDeclarations( node.nodeName, node );
                xml.removeFromCollection( node );
            }
        }

        // Process the remaining template nodes
        for ( node in xml ) {
            processNode( node );
        }

        // More escaping hoop-jumping.  Basically, xml.html() will encode the text nodes, but not the attributes. Gaarrrh
        // So if we go through the attributes on each of our top level nodes, and escape them, then we can unescape the whole thing.
        for (node in xml)
            if (node.isElement())
                for (att in node.attributes())
                    node.setAttr(att, node.attr(att).htmlEscape());

        var html = xml.html().htmlUnescape();

        return { template: html, fields: fieldsToAdd };
    }

    static function processNode( node:DOMNode ) {
        if (node.tagName() == "dtx:loop")
        {
            // It's a loop element... either: 
            //    <dtx:loop><dt>$name</dt><dd>$age</dd></dtx:loop> OR
            //    <dtx:loop partial="Something" />
            loopNumber++;
            processLoop(node, loopNumber);
        }
        else if (node.tagName().startsWith('dtx:'))
        {
            // This is a partial call.  <dtx:_MyPartial /> or <dtx:SomePartial /> etc
            partialNumber++;
            processPartialCalls(node, partialNumber);
        }
        else if ( node.isElement() || node.isDocument() )
        {
            // process attributes on elements
            if ( node.isElement() ) processAttributes(node);

            // recurse documents and elements
            for ( child in node.children(false) ) processNode( child );
        }
        else if (node.isTextNode())
        {
            // look for variable interpolation eg "Welcome back, $name..."
            if (node.text().indexOf('$') > -1)
            {
                interpolateTextNodes(node);
            }
            // Get rid of HTML encoding.  Haxe3 does this automatically, but we want it to remain unencoded.  
            // (I think?  While it might be nice to have it do the encoding for you, it is not expected, so violates principal of least surprise.  Also, how does '&nbsp;' get entered?)
            // And it appears to only affect the top level element, not any descendants.  Weird...
            node.setText(node.text().htmlUnescape());
            clearWhitespaceFromTextnode(node);
        }
    }

    static function clearWhitespaceFromTextnode(node:dtx.DOMNode)
    {
        var text = node.text();
        if (node.prev() == null)
        {
            // if it's the first, get rid of stuff at the start
            var re = ~/^\s+/g;
            text = re.replace(text, "");
        }
        if (node.next() == null)
        {
            // if it's the last node, get rid of stuff at the end
            var re = ~/\s+$/g;
            text = re.replace(text, "");   
        }

        if (text == "" || ~/^\s+$/.match(text))
            node.removeFromDOM();
        else 
            node.setText(text);
    }
    
    static function processPartialDeclarations(name:String, node:dtx.DOMNode, ?fields:Array<Field>, ?useKeepWidget=false)
    {
        var p = Context.currentPos();
        var localClass = haxe.macro.Context.getLocalClass();
        var pack = localClass.get().pack;
        if ( node.attr('keep')=="true" ) useKeepWidget = true;
        
        // Before getting the partial TPL, let's clear out any whitespace
        for (d in node.descendants(false))
        {
            if (d.isTextNode())
            {
                clearWhitespaceFromTextnode(d);
            }
        }

        var partialTpl = node.innerHTML();

        var className = localClass.get().name + name;
        var classMeta = [{
            pos: p,
            params: [Context.makeExpr(partialTpl, p)],
            name: ":template"
        }];
        for ( meta in localClass.get().meta.get() ) 
            classMeta.push(meta);

        // Find out if the type has already been defined
        var existingClass:Null<haxe.macro.Type>;
        try { existingClass = Context.getType(className); }
        catch (e:Dynamic) { existingClass = null; }

        if (existingClass != null)
        {
            switch (existingClass)
            {
                case TInst(t, _):
                    var classType = t.get();
                    var metaAccess = classType.meta;
                    if (metaAccess.has(":template") == false && metaAccess.has(":loadTemplate") == false)
                    {
                        // No template has been defined, use ours
                        metaAccess.add(":template", [Context.makeExpr(partialTpl, p)], p);
                    }
                default:
            }
        }
        else 
        {
            var classKind = TypeDefKind.TDClass({
                sub: null,
                params: [],
                pack: ['dtx','widget'],
                name: (useKeepWidget) ? "KeepWidget" : "Widget"
            });
            if (fields==null) fields = [];

            var partialDefinition = {
                pos: p,
                params: [],
                pack: pack,
                name: className,
                meta: classMeta,
                kind: classKind,
                isExtern: false,
                fields: fields
            };
            haxe.macro.Context.defineType(partialDefinition);
        }
    }

    static function processPartialCalls(node:dtx.DOMNode, t:Int)
    {
        // Elements beginning with <dtx:SomeTypeName /> or <dtx:my.package.SomeTypeName />
        // May have attributes <dtx:Button text="Click Me" />

        // Generate a name for the partial.  Either take it from the <dtx:MyPartial dtx-name="this" /> attribute,
        // or autogenerate one (partial_$t, t++)
        var widgetClass = haxe.macro.Context.getLocalClass();
        var nameAttr = node.attr('dtx-name');
        var name = (nameAttr != "") ? nameAttr : "partial_" + t;
        var p = Context.currentPos();

        // Resolve the type for the partial.  If it begins with dtx:_, then it is local to this file.
        // Otherwise, just resolve it as a class name.
        var typeName = node.nodeName.substring(4);
        if (typeName.startsWith("_"))
        {
            // partial inside this file
            typeName = widgetClass.get().name + typeName;
        }
        // If we ever allow importing partials by fully qualified name, the macro parser does not support
        // having a '.' in the Xml Element Name.  So replace them with a ":", and we'll substitute them
        // back here.  For now though, I couldn't get it to work so I'll leave this disabled.
        //typeName = (typeName.indexOf(':') > -1) ? typeName.replace(':', '.') : typeName;

        var pack = [];
        var type = try {
            Context.getType(typeName);
        } catch (e:String) {
            if ( e=="Type not found '" + typeName + "'" ) 
                Context.fatalError('Unable to find Widget/Partial "$typeName" in widget template $widgetClass', widgetClass.get().pos);
            else throw e;
        }

        // Alternatively use: type = Context.typeof(macro new $typeName()), see what works
        var classType:Ref<ClassType>;
        switch (type)
        {
            case TInst(t,_):
                // get the type
                classType = t;
                pack = classType.get().pack;
            default: 
                throw "Asked for partial " + typeName + " but that doesn't appear to be a class";
        }
        
        // Replace the call with <div data-dtx-partial="$name"></div>
        var partialDOM = templates.get( classType.toString() ).parse();
        var partialFirstElement = partialDOM.filter( function (n) return n.isElement() ).getNode(0);
        var placeholderName = (partialFirstElement!=null) ? partialFirstElement.tagName() : "span";
        node.replaceWith( placeholderName.create().setAttr("data-dtx-partial", name) );

        // Set up a public field in the widget, public var $name(default,set_$name):$type
        var propType = TPath({
            sub: null,
            params: [],
            pack: pack,
            name: typeName
        });
        var prop = BuildTools.getOrCreateProperty(name, propType, false, true);
        var variableRef = name.resolve();
        var typeRef = typeName.resolve();

        // Add some lines to the setter
        var selector = ("[data-dtx-partial='" + name + "']").toExpr();
        var linesToAdd = macro {
            // Either replace the existing partial, or if none set, replace the <div data-dtx-partial='name'/> placeholder
            var toReplace = ($variableRef != null) ? $variableRef : dtx.collection.Traversing.find(this, $selector);
            dtx.collection.DOMManipulation.replaceWith(toReplace, v);
        }
        BuildTools.addLinesToFunction(prop.setter, linesToAdd, 0);

        // Now that we can set it via the property setter, we do so in our init function.
        // With something like:
        // 
        // $name = new $type()
        // this.find("[data-dtx-partial=$name]").replaceWith($name)
        //
        // So that'll end up looking like:
        //
        // public function new() {
        //   var btn = new Button();
        //   partial_1 = btn;
        // }

        // Get the init function, instantiate our partial
        var initFn = BuildTools.getOrCreateField(getInitFnTemplate());
        linesToAdd = macro {
            $variableRef = new $typeName();
        };
        BuildTools.addLinesToFunction(initFn, linesToAdd);

        // Any attributes on the partial are variables to be passed.  Every time a setter on the parent widget is called, it should trigger the relevent setter on the child widget
        for (attName in node.attributes())
        {
            if (attName != "dtx-name")
            {
                var propertyRef = '$name.$attName'.resolve();
                var valueExprStr = node.attr(attName);
                var valueExpr = 
                    try 
                        Context.parse( valueExprStr, p )
                    catch (e:Dynamic) 
                        Context.fatalError('Error parsing $attName="$valueExprStr" in $typeName partial call ($widgetClass template). \nError: $e \nNode: ${node.html()}', p);
                
                var idents =  valueExpr.extractIdents();
                var setterExpr = macro $propertyRef = $valueExpr;
                if ( idents.length>0 ) 
                    // If it has variables, set it in all setters
                    addExprToAllSetters(setterExpr,idents, true);
                else
                    // If it doesn't, set it in init
                    BuildTools.addLinesToFunction(initFn, setterExpr);
            
            }
        }
    }

    static function processLoop(node:dtx.DOMNode, t:Int)
    {
        // Generate a name for the partial.  Either take it from the <dtx:MyPartial dtx-name="this" /> attribute,
        // or autogenerate one (partial_$t, t++)
        var widgetClass = haxe.macro.Context.getLocalClass();
        var nameAttr = node.attr('dtx-name');
        var name = (nameAttr != "") ? nameAttr : "loop_" + t;
        var p = widgetClass.get().pos;

        // Get the `for="name in names"` attribute
        var propName:Null<String> = null;
        var loopInputCT:ComplexType;
        var typingFailure:Error = null;
        var iterableExpr:Null<Expr> = null;
        var forAttr = node.attr( "for" );
        var typeAttr = node.attr( "type" );
        if ( forAttr!="" ) {
            var forCode = 'for ($forAttr) {}';
            try {
                var forExpr = Context.parse( forCode, p );
                switch (forExpr.expr) {
                    case EFor( { expr: EIn(e1,e2), pos: _ }, _ ): 
                        switch (e1.expr) {
                            case EConst(CIdent(n)): 
                                propName = n;
                            case _: 
                                throw 'Was expecting EConst(CIdent(propName)), but got $e1';
                        }
                        // For "typeof" to work, it needs us to mock member variables so it knows what type they are
                        var variablesInContext = [];
                        for ( field in BuildTools.getFields() ) {
                            switch (field.kind) {
                                case FVar(ct,_), FProp(_,_,ct,_): 
                                    variablesInContext.push({ name: field.name, type: ct, expr: null });
                                case _:
                            }
                        }
                        switch e2.typeof(variablesInContext) {
                            case Success(itType): 
                                var result;
                                if ( Context.unify(itType, Context.getType("Iterable")) ) {
                                    result = (macro $e2.iterator().next()).typeof(variablesInContext);
                                }
                                else if ( Context.unify(itType, Context.getType("Iterator")) ) {
                                    result = (macro $e2.next()).typeof(variablesInContext);
                                }
                                else throw "$e2 Was not an iterable or an iterator";

                                switch (result) {
                                    case Success(t): loopInputCT = t.toComplexType();
                                    case Failure(err): typingFailure = err;
                                }
                            case Failure(err): typingFailure = err;
                        }

                        iterableExpr = e2;
                    case _: 
                        throw "Was expecting EFor, got something else";
                }
            }
            catch (e:Dynamic)
                Context.fatalError('Error parsing for="$forAttr" in loop ($widgetClass template). \nError: $e \nNode: ${node.html()}', p);
        }
        if ( loopInputCT==null && typeAttr!="" ) {
            var typeName = "";
            if ( typeAttr.indexOf(":") > -1 ) {
                var parts = typeAttr.split(":");
                propName = parts[0].trim();
                typeName = parts[1].trim();
            }
            else {
                typeName = typeAttr.trim();
            }
            var type = Context.getType( typeName );
            if (type==null) 
                Context.fatalError('Error finding type type="$typeAttr" in loop ($widgetClass template). \nType $typeName was not found.  \nNode: ${node.html()}', p);
            loopInputCT = type.toComplexType();
        }
        if ( loopInputCT==null ) {
            Context.warning( 'Unable to type dtx:loop:\n$node', p );
            if (typingFailure!=null) typingFailure.throwSelf();
            Context.fatalError( "Exiting", p );
        }
        else {
            // Check if a partial is specified, if not, use InnerHTML to define a new partial 
            var partialTypeName = node.attr("partial");
            if ( partialTypeName=="" ) {
                var partialHtml = node.innerHTML();
                if ( partialHtml.length==0 )
                    Context.fatalError( 'You must define either a partial="" attribute, or have child elements for the dtx:loop in widget $widgetClass', p );
                
                // Process the template as a partial declaration
                partialTypeName = "_" + name.charAt(0).toUpperCase() + name.substr(1);

                if ( propName!=null ) {
                    var propertyToAdd:Field = {
                        pos: p,
                        name: propName,
                        meta: [],
                        kind: FVar(loopInputCT,null),
                        doc: null,
                        access: [APublic]
                    };
                    processPartialDeclarations( partialTypeName, node, [ propertyToAdd ], true );
                }
            }
            
            // Set up the full name for relative partials 
            if (partialTypeName.startsWith("_"))
            {
                partialTypeName = widgetClass.get().name + partialTypeName;
            }


            // Extract the ClassType for the chosen type
            var partialClassType:Ref<ClassType>;
            try {
                switch ( Context.getType(partialTypeName) )
                {
                    case TInst(t,_):
                        // get the type
                        partialClassType = t;
                    default: 
                        throw "Asked for loop partial " + partialTypeName + " but that doesn't appear to be a class";
                }
            } catch (e:String) {
                if ( e=="Type not found '" + partialTypeName + "'" ) 
                    Context.fatalError('Unable to find Loop Widget/Partial "$partialTypeName" in widget template $widgetClass', p);
                else throw e;
            }
            
            // Replace the call with <div data-dtx-loop="$name"></div>
            var partialDOM = templates.get( partialClassType.toString() ).parse();
            var partialFirstElement = partialDOM.filter( function (n) return n.isElement() ).getNode(0);
            var placeholderName = (partialFirstElement!=null) ? partialFirstElement.tagName() : "span";
            node.replaceWith( placeholderName.create().setAttr("data-dtx-loop", name) );

            // Set up a public field in the widget, public var $loopName(default,set_$name):WidgetLoop<$inputCT,$widgetCT>
            var widgetTypePath = TPath({
                sub: null,
                params: [],
                pack: partialClassType.get().pack,
                name: partialTypeName
            });
            var inputTypeParam = TPType( loopInputCT );
            var widgetTypeParam = TPType( widgetTypePath );
            var loopPropType = TPath( {
                sub: null,
                params: [ inputTypeParam, widgetTypeParam ],
                pack: ["dtx","widget"],
                name: "WidgetLoop"
            });
            var prop = BuildTools.getOrCreateProperty(name, loopPropType, false, true);
            
            // Add some lines to the setter
            var variableRef = name.resolve();
            var partialTypeRef = partialTypeName.resolve();
            var selector = ("[data-dtx-loop='" + name + "']").toExpr();
            var linesToAdd = macro {
                // Either replace the existing partial, or if none set, replace the <div data-dtx-partial='name'/> placeholder
                var toReplace = ($variableRef != null) ? $variableRef : dtx.collection.Traversing.find(this, $selector);
                dtx.collection.DOMManipulation.replaceWith(toReplace, v);
            }
            BuildTools.addLinesToFunction(prop.setter, linesToAdd, 0);

            // Get the join information
            var join = node.attr("join");
            var finalJoin = node.attr("finaljoin");
            var afterJoin = node.attr("after");
            var joinExpr = Context.makeExpr( (join!="") ? join : null, p );
            var finalJoinExpr = Context.makeExpr( (finalJoin!="") ? finalJoin : null, p );
            var afterJoinExpr = Context.makeExpr( (afterJoin!="") ? afterJoin : null, p );

            // Get the init function, instantiate our loop object
            var initFn = BuildTools.getOrCreateField(getInitFnTemplate());
            var propNameExpr = Context.makeExpr( propName, p );
            linesToAdd = macro {
                // new WidgetLoop($Partial, $varName, propmap=null, automap=true)
                $variableRef = new dtx.widget.WidgetLoop($partialTypeRef, $propNameExpr, null, true);
                $variableRef.setJoins($joinExpr, $finalJoinExpr, $afterJoinExpr);
            };
            BuildTools.addLinesToFunction(initFn, linesToAdd);

            // Find any variables mentioned in the iterable / for loop, and add to our setter
            if ( iterableExpr!=null ) {
                var idents = iterableExpr.extractIdents();
                var setterExpr = macro 
                    try 
                        $variableRef.setList( $iterableExpr ) 
                    catch (e:Dynamic) {
                        if ($variableRef!=null)
                            $variableRef.empty();
                    }

                if ( idents.length>0 ) 
                    // If it has variables, set it in all setters
                    addExprToAllSetters(setterExpr,idents, true);
                else
                    // If it doesn't, set it in init
                    BuildTools.addLinesToFunction(initFn, setterExpr);
            }
        }

    }

    static function getInitFnTemplate()
    {
        var body = macro {};
        return {
            pos: Context.currentPos(),
            name: "init",
            meta: [],
            kind: FieldType.FFun({
                    ret: null,
                    params: [],
                    expr: body,
                    args: []
                }),
            doc: "",
            access: [APrivate,AOverride]
        }
    }

    static function processAttributes(node:dtx.DOMNode)
    {
        // A regular element
        for (attName in node.attributes())
        {
            if (attName.startsWith('dtx-on-'))
            {
                // this is not a boolean, does it need to be processed separately?
            }
            else if (attName == 'dtx-loop')
            {
                // loop this element...
            }
            else if (attName == 'dtx-value')
            {
                // Every time the value changes, change this.
            }
            else if (attName == 'dtx-name')
            {
                var name = node.attr(attName);
                node.removeAttr(attName);
                createNamedPropertyForElement(node, name);
            }
            else if (attName.startsWith('dtx-'))
            {
                // look for special attributes eg <ul dtx-show="hasItems" />
                var wasDtxAttr = processDtxBoolAttributes(node, attName);
            }
            else 
            {
                // look for variable interpolation eg <div id="person_$name">...</div>
                if (node.get(attName).indexOf('$') > -1)
                {
                    interpolateAttributes(node, attName);
                }
            }
        }
    }

    static function createNamedPropertyForElement(node:dtx.DOMNode, name:String)
    {
        if (name != "")
        {
            var selector = getUniqueSelectorForNode(node); // Returns for example: dtx.collection.Traversing.find(this, $selectorTextAsExpr)

            // Set up a public field in the widget, public var $name(default,set_$name):$type
            var propType = TPath({
                sub: null,
                params: [],
                pack: ['dtx'],
                name: "DOMCollection"
            });
            var prop = BuildTools.getOrCreateProperty(name, propType, true, false);
            
            // Change the setter to null
            switch (prop.property.kind)
            {
                case FieldType.FProp(get, _, t, e):
                    prop.property.kind = FieldType.FProp(get, "null", t, e);
                default:
            }

            // Change the getter body
            switch( prop.getter.kind )
            {
                case FFun(f):
                    f.expr = macro return dtx.Tools.toCollection($selector);
                default: 
            }
        }
    }

    static var uniqueDtxID:Int = 0;
    
    /** Get a unique selector for the node, creating a data attribute if necessary */
    static function getUniqueSelectorForNode(node:dtx.DOMNode):Expr
    {
        // Get an existing data-dtx-id, or set a new one 
        var id:Int;
        var attValue = node.attr("data-dtx-id");
        if (attValue=="") 
        {
            id = uniqueDtxID++;
            node.setAttr("data-dtx-id", '$id');
        }
        else 
        {
            id = Std.parseInt(attValue);
        }

        var idExpr = id.toExpr();
        return macro _dtxWidgetNodeIndex[$idExpr];
    }

    static function interpolateAttributes(node:dtx.DOMNode, attName:String)
    {
        var selectorExpr = getUniqueSelectorForNode(node);

        var nameAsExpr = Context.makeExpr(attName, Context.currentPos());

        var result = processVariableInterpolation(node.attr(attName));
        var interpolationExpr = result.expr;
        var variablesInside = result.variablesInside;

        // Set up bindingExpr
        //var bindingExpr = macro this.find($selectorAsExpr).setAttr($nameAsExpr, $interpolationExpr);
        var bindingExpr = macro dtx.single.ElementManipulation.setAttr($selectorExpr, $nameAsExpr, $interpolationExpr);
        
        // Go through array of all variables again
        addExprToAllSetters(bindingExpr, variablesInside, true);
    }

    static function interpolateTextNodes(node:dtx.DOMNode)
    {
        // Get (or set) ID on parent, get selector
        var selectorAsExpr = getUniqueSelectorForNode(node.parent);
        var index = node.index();
        var indexAsExpr = index.toExpr();
        
        var result = processVariableInterpolation(node.text());
        var interpolationExpr = result.expr;
        var variablesInside = result.variablesInside;

        // Set up bindingExpr
        //var bindingExpr = macro this.children(false).getNode($indexAsExpr).setText($interpolationExpr);
        var bindingExpr = macro dtx.single.ElementManipulation.setText(dtx.single.Traversing.children($selectorAsExpr, false).getNode($indexAsExpr), $interpolationExpr);
        
        // Add binding expression to all setters.  
        addExprToAllSetters(bindingExpr, variablesInside, true);

        // Initialise variables
        addExprInitialisationToConstructor(variablesInside);
    }

    static function addExprToAllSetters(expr:Expr, variables:Array<String>, ?prepend)
    {
        if (variables.length == 0)
        {
            // Add it to the init() function instead instead
            var initFn = BuildTools.getOrCreateField(getInitFnTemplate());
            BuildTools.addLinesToFunction(initFn, expr);
        }

        for (varName in variables)
        {
            // Add bindingExpr to every setter.  Add at position `1`, so after the first line, which should be 'this.field = v;'
            if (varName.fieldExists())
            {
                varName.getField().getSetter().addLinesToFunction(expr, 1);
            }
            else throw ('Field $varName not found in ${Context.getLocalClass()}');
        }
    }

    static function addExprInitialisationToConstructor(variables:Array<String>)
    {
        for (varName in variables)
        {
            var field = varName.getField();
            switch (field.kind)
            {
                case FProp(get,set,type,e):
                    var initValueExpr:Expr = null;
                    var initFn = BuildTools.getOrCreateField(getInitFnTemplate());
                    if ( e!=null ) 
                        initValueExpr = e;
                    else 
                    {
                        if ( type == null ) throw 'Unknown type when trying to initialize $varName on class ${Context.getLocalClass()}';
                        switch (type)
                        {
                            case TPath(path):
                                var name = path.name;
                                if ( name=="StdTypes" ) name = path.sub;
                                switch (name) {
                                    case "Bool": 
                                        initValueExpr = macro false;
                                    case "String": 
                                        initValueExpr = macro "";
                                    case "Int": 
                                        initValueExpr = macro 0;
                                    case "Float": 
                                        initValueExpr = macro 0;
                                    default: 
                                        initValueExpr = macro null;
                                }
                            default:
                        }
                    }
                    if ( initValueExpr!=null )
                    {
                        // Update the init expression, and add to the init function
                        // We want both, the init function so that setters fire, and the init expression
                        // so that all values are initialized by the time the first setter fires also...
                        field.kind = FProp(get,set,type,initValueExpr);
                        var varRef = varName.resolve();
                        var setExpr = macro $varRef = $initValueExpr;
                        BuildTools.addLinesToFunction(initFn, setExpr);
                    }
                default:
            }
        }
    }

    static function processVariableInterpolation(string:String):{ expr:Expr, variablesInside:Array<String> }
    {
        var stringAsExpr = Context.makeExpr(string, Context.currentPos());
        var interpolationExpr = Format.format(stringAsExpr);
        
        // Get an array of all the variables in interpolationExpr
        var variables:Array<ExtractedVarType> = extractVariablesUsedInInterpolation(interpolationExpr);
        var variableNames:Array<String> = [];

        for (extractedVar in variables)
        {
            switch (extractedVar)
            {
                case Ident(varName):
                    var propType = TPath({
                        sub: null,
                        params: [],
                        pack: [],
                        name: "String"
                    });
                    var prop = BuildTools.getOrCreateProperty(varName, propType, false, true);

                    var functionName = "print_" + varName;
                    if (BuildTools.fieldExists(functionName))
                    {
                        // If yes, in interpolationExpr replace calls to $name with print_$name($name)
                        var replacements = {};
                        Reflect.setField( replacements, varName, macro $i{functionName}() );
                        interpolationExpr = interpolationExpr.substitute( replacements );
                    }
                    variableNames.push(varName);
                case Call(varName):
                    variableNames.push(varName);
                case Field(varName):
                    interpolationExpr = macro (($i{varName} != null) ? $interpolationExpr : "");
                    variableNames.push(varName);
            }
        }

        return {
            expr: interpolationExpr,
            variablesInside: variableNames
        };
    }

    /** Takes the output of an expression such as Std.format(), and searches for variables used... 
    Basic implementation so far, only looks for basic EConst(CIdent(myvar)) */
    public static function extractVariablesUsedInInterpolation(expr:Expr)  
    {
        var variablesInside:Array<ExtractedVarType> = [];
        switch(expr.expr)
        {
            case ECheckType(e,_):
                switch (e.expr)
                {
                    case EBinop(_,_,_):
                        var parts = BuildTools.getAllPartsOfBinOp(e);
                        for (part in parts)
                        {
                            switch (part.expr)
                            {
                                case EConst(CIdent(varName)):
                                    variablesInside.push( ExtractedVarType.Ident(varName) );
                                case EField(e, field):
                                    // Get the left-most field, add it to the array
                                    var leftMostVarName = getLeftMostVariable(part);
                                    if (leftMostVarName != null) {
                                        if ( leftMostVarName.fieldExists() )
                                            variablesInside.push( ExtractedVarType.Field(leftMostVarName) );
                                        else {
                                            var localClass = Context.getLocalClass();
                                            var printer = new Printer("  ");
                                            var partString = printer.printExpr(part);
                                            Context.fatalError('In the Detox template for $localClass, in the expression `$partString`, variable "$leftMostVarName" could not be found.  Variables used in complex expressions inside the template must be explicitly declared.', localClass.get().pos);
                                        }
                                    }
                                case ECall(e, params):
                                    // Look for variables to add in the paramaters
                                    for (param in params) {
                                        var varName = getLeftMostVariable(param);
                                        if (varName != null) {
                                            if ( varName.fieldExists() )
                                                variablesInside.push( ExtractedVarType.Call(varName) );
                                            else {
                                                var localClass = Context.getLocalClass();
                                                var printer = new Printer("  ");
                                                var callString = printer.printExpr(part);
                                                Context.fatalError('In the Detox template for $localClass, in function call `$callString`, variable "$varName" could not be found.  Variables used in complex expressions inside the template must be explicitly declared.', localClass.get().pos);
                                            }
                                        }
                                    }
                                    // See if the function itself is on a variable we need to add
                                    var leftMostVarName = getLeftMostVariable(e);
                                    if ( leftMostVarName.fieldExists() ) {
                                        switch ( leftMostVarName.getField().kind ) {
                                            case FVar(_,_) | FProp(_,_,_,_):
                                                variablesInside.push( ExtractedVarType.Field(leftMostVarName) );
                                            case _:
                                        }
                                    }
                                    // else: don't throw error.  They might be doing "haxe.crypto.Sha1.encode()" or "Math.max(a,b)" etc. If they do something invalid the compiler will catch it, the error message just won't be as obvious
                                default:
                                    // do nothing
                            }
                        }
                    default:
                        haxe.macro.Context.fatalError("extractVariablesUsedInInterpolation() only works when the expression inside ECheckType is EBinOp, as with the output of Format.format()", Context.currentPos());
                }
            default:
                haxe.macro.Context.fatalError("extractVariablesUsedInInterpolation() only works on ECheckType, the output of Format.format()", Context.currentPos());
        }

        return variablesInside;
    }

    /** Takes an expression and tries to find the left-most plain variable.  For example "student" in `student.name`, "age" in `person.age`, "name" in `name.length`.
    
    It will try to ignore "this", for example it will match "person" in `this.person.age`.

    Note it will also match packages: "haxe" in "haxe.crypto.Sha1.encode"
    */
    public static function getLeftMostVariable(expr:Expr):Null<String>
    {
        var leftMostVarName = null;
        var error = false;

        switch (expr.expr)
        {
            case EConst(CIdent(varName)):
                leftMostVarName = varName;
            case EField(e, field):
                // Recurse until we find it.
                var currentExpr = e;
                var currentName:String;
                while ( leftMostVarName==null ) {
                    switch ( currentExpr.expr ) {
                        case EConst(CIdent(varName)): 
                            if (varName == "this") 
                                leftMostVarName = currentName;
                            else 
                                leftMostVarName = varName;
                        case EField(e, field): 
                            currentName = field;
                            currentExpr = e;
                        case _: 
                            error = true;
                            break;
                    }
                }
            case EConst(_): // A constant.  Leave it null
            case _: error = true;
        }
        if (error)
        {
            var localClass = Context.getLocalClass();
            var printer = new Printer("  ");
            var exprString = printer.printExpr( expr );
            Context.fatalError('In the Detox template for $localClass, the expression `$exprString`, was too complicated for the poor Detox macro to understand.', localClass.get().pos);
        }

        return leftMostVarName;
    }

    static function processDtxBoolAttributes(node:dtx.DOMNode, attName:String)
    {
        var wasDtxAttr = false;
        var trueStatement:Expr = null;
        var falseStatement:Expr = null;

        if (attName.startsWith('dtx-'))
        {
            wasDtxAttr = true; // probably true
            var selector = getUniqueSelectorForNode(node);
            switch (attName)
            {
                case "dtx-show":
                    var className = "hidden".toExpr();
                    trueStatement = macro dtx.single.ElementManipulation.removeClass($selector, $className);
                    falseStatement = macro dtx.single.ElementManipulation.addClass($selector, $className);
                case "dtx-hide":
                    var className = "hidden".toExpr();
                    trueStatement = macro dtx.single.ElementManipulation.addClass($selector, $className);
                    falseStatement = macro dtx.single.ElementManipulation.removeClass($selector, $className);
                case "dtx-enabled":
                    trueStatement = macro dtx.single.ElementManipulation.removeAttr($selector, "disabled");
                    falseStatement = macro dtx.single.ElementManipulation.setAttr($selector, "disabled", "disabled");
                case "dtx-disabled":
                    trueStatement = macro dtx.single.ElementManipulation.setAttr($selector, "disabled", "disabled");
                    falseStatement = macro dtx.single.ElementManipulation.removeAttr($selector, "disabled");
                case "dtx-checked":
                    trueStatement = macro dtx.single.ElementManipulation.setAttr($selector, "checked", "checked");
                    falseStatement = macro dtx.single.ElementManipulation.removeAttr($selector, "checked");
                case "dtx-unchecked":
                    trueStatement = macro dtx.single.ElementManipulation.removeAttr($selector, "checked");
                    falseStatement = macro dtx.single.ElementManipulation.setAttr($selector, "checked", "checked");
                default:
                    if (attName.startsWith('dtx-class-'))
                    {
                        // add a class
                        var className = attName.substring(10);
                        var classNameAsExpr = className.toExpr();
                        trueStatement = macro dtx.single.ElementManipulation.addClass($selector, $classNameAsExpr);
                        falseStatement = macro dtx.single.ElementManipulation.removeClass($selector, $classNameAsExpr);
                    }
                    else
                    {
                        wasDtxAttr = false; // didn't match, set back to false
                    }
            }
        }

        if (wasDtxAttr)
        {
            var className = Context.getLocalClass().toString();
            var classPos = Context.getLocalClass().get().pos;

            // Turn the attribute into an expression, and check it is a Bool, so we can use it in an if statement
            var testExprStr = node.attr(attName);
            var testExpr = 
                try 
                    Context.parse( testExprStr, classPos )
                catch (e:Dynamic) 
                    Context.fatalError('Error parsing $attName="$testExprStr" in $className template. \nError: $e \nNode: ${node.html()}', classPos);

            // Extract all the variables used, create the `if(test) ... else ...` expr, add to setters, initialize variables
            var idents =  testExpr.extractIdents();
            var bindingExpr = macro if ($testExpr) $trueStatement else $falseStatement;
            addExprToAllSetters(bindingExpr,idents, true);
            addExprInitialisationToConstructor(idents);

            // Remove the attribute now that we've processed it
            node.removeAttr(attName);
        }
            
        return wasDtxAttr;
    }

    static var booleanSetters:Map<String,Map<String, { trueBlock:Array<Expr>, falseBlock:Array<Expr> }>> = null;
    static function getBooleanSetterParts(booleanName:String)
    {
        // If a list of boolean setters for this class doesn't exist yet, set one up
        var className = Context.getLocalClass().toString();
        if (booleanSetters == null) booleanSetters = new Map();
        if (booleanSetters.exists(className) ==  false) booleanSetters.set(className, new Map());

        // If this boolean setter doesn't exist yet, create it.  
        if (booleanSetters.get(className).exists(booleanName) == false)
        {
            // get or create property
            var propType = TPath({
                sub: null,
                params: [],
                pack: [],
                name: "Bool"
            });
            var prop = BuildTools.getOrCreateProperty(booleanName, propType, false, true);

            // add if() else() to setter, at position 1 (so after the this.x = x; statement)
            var booleanExpr = booleanName.resolve();
            var ifStatement = macro if ($booleanExpr) {} else {};
            BuildTools.addLinesToFunction(prop.setter, ifStatement, 1);

            // get the trueBlock and falseBlock
            var trueBlock:Array<Expr>;
            var falseBlock:Array<Expr>;
            switch (ifStatement.expr)
            {
                case EIf(_,eif,eelse):
                    switch (eif.expr)
                    {
                        case EBlock(b):
                            trueBlock = b;
                        default: 
                            throw "Error in WidgetTools: this should definitely have been an EBlock";
                    }
                    switch (eelse.expr)
                    {
                        case EBlock(b):
                            falseBlock = b;
                        default: 
                            throw "Error in WidgetTools: this should definitely have been an EBlock";
                    }
                default:
                    throw "Error in WidgetTools: this should definitely have been an EIf";
            }

            // Keep track of them so we can use them later
            booleanSetters.get(className).set(booleanName, {
                trueBlock: trueBlock,
                falseBlock: falseBlock
            });
        }

        // get the if block and else block and return them
        return booleanSetters.get(className).get(booleanName);
    }

    #end
}

// for the glory of God