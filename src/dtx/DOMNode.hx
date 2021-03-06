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

package dtx;

#if js
	#if haxe3
		typedef NodeList = js.html.NodeList;
		typedef DOMNode = js.html.Node;
		typedef DOMElement = js.html.Element;
		typedef Event = js.html.Event;
	#else
		import js.w3c.level3.Core;
		typedef NodeList = js.w3c.level3.Core.NodeList;
		typedef DOMNode = js.w3c.level3.Core.Node;
		typedef DOMElement = js.w3c.level3.Core.Element;
		typedef Event = js.w3c.level3.Events.Event;
	#end 
	typedef DocumentOrElement = {> DOMNode,
		var querySelector:String->Dynamic->DOMElement;
		var querySelectorAll:String->Dynamic->NodeList;
	}
#else 
	typedef DOMNode = Xml;
	typedef DOMElement = DOMNode;
	typedef DocumentOrElement = DOMNode;
#end


