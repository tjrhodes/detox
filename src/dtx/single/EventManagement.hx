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

package dtx.single;

import dtx.DOMNode;
import js.html.*;

class EventManagement
{
	/** Trigger an event, as if it has actually happened */
	public static inline function trigger(target:DOMNode, eventString:String):DOMNode
	{
		#if js 
		if (target!=null) Bean.fire(target, eventString);
		#else 
		trace ("Detox events only work on the Javascript target, sorry.");
		#end
		return target;
	}

	/** add an event listener */
	public static inline function on(target:DOMNode, eventType:String, ?selector:String, ?listener:EventListener):DOMNode
	{
		#if js 
			if (target != null)
			{
				if (listener != null)
				{
					if (selector!=null) Bean.on(target, eventType, selector, listener);
					else Bean.on(target, eventType, listener);
				}
				else trigger (target, eventType);
			}
		#else 
			trace ("Detox events only work on the Javascript target, sorry.");
		#end
		return target;
	}

	public static function off(target:DOMNode, ?eventType:String = null, ?listener:EventListener=null):DOMNode
	{
		#if js 
			if (target != null)
			{
				if (eventType != null && listener != null) Bean.off(target, eventType, listener);
				else if (eventType != null) Bean.off(target, eventType);
				else if (listener != null) Bean.off(target, listener);
				else Bean.off(target);
			}
		#else 
			trace ("Detox events only work on the Javascript target, sorry.");
		#end
		return target;
	}

	/** Attach an event but only let it run once */
	public static function one(target:DOMNode, eventType:String, ?selector:String, listener:EventListener):DOMNode
	{
		#if js 
			if (target != null)
			{
				if (selector != null) Bean.one(target, eventType, selector, listener);
				else Bean.one(target, eventType, listener);
			}
		#else 
			trace ("Detox events only work on the Javascript target, sorry.");
		#end
		return target;
	}

	public static inline function mousedown(target:DOMNode, ?selector:String, ?listener:MouseEvent->Void):DOMNode
	{
		return on(target, "mousedown", selector, untyped listener);
	}

	public static inline function mouseenter(target:DOMNode, ?selector:String, ?listener:MouseEvent->Void):DOMNode
	{
		return on(target, "mouseover", selector, untyped listener);
	}

	public static inline function mouseleave(target:DOMNode, ?selector:String, ?listener:MouseEvent->Void):DOMNode
	{
		return on(target, "mouseout", selector, untyped listener);
	}

	public static inline function mousemove(target:DOMNode, ?selector:String, ?listener:MouseEvent->Void):DOMNode
	{
		return on(target, "mousemove", selector, untyped listener);
	}

	public static inline function mouseout(target:DOMNode, ?selector:String, ?listener:MouseEvent->Void):DOMNode
	{
		return on(target, "mouseout", selector, untyped listener);
	}

	public static inline function mouseover(target:DOMNode, ?selector:String, ?listener:MouseEvent->Void):DOMNode
	{
		return on(target, "mouseover", selector, untyped listener);
	}

	public static inline function mouseup(target:DOMNode, ?selector:String, ?listener:MouseEvent->Void):DOMNode
	{
		return on(target, "mouseup", selector, untyped listener);
	}

	public static inline function keydown(target:DOMNode, ?selector:String, ?listener:KeyboardEvent->Void):DOMNode
	{
		return on(target, "keydown", selector, untyped listener);
	}

	public static inline function keypress(target:DOMNode, ?selector:String, ?listener:KeyboardEvent->Void):DOMNode
	{
		return on(target, "keypress", selector, untyped listener);
	}

	public static inline function keyup(target:DOMNode, ?selector:String, ?listener:KeyboardEvent->Void):DOMNode
	{
		return on(target, "keyup", selector, untyped listener);
	}

	public static function hover(target:DOMNode, ?selector:String, listener1:MouseEvent->Void, ?listener2:MouseEvent->Void = null):DOMNode
	{
		mouseenter(target, selector, listener1);

		if (listener2 == null)
		{
			// no 2nd listener, that means run the first again
			mouseleave(target, selector, listener1);
		}
		else
		{
			// there is a second listener, so run that when the mouse leaves the hover-area
			mouseleave(target, selector, listener2);
		}
		return target;
	}

	public static inline function submit(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "submit", selector, listener);
	}

	public static function toggleClick(target:DOMNode, ?selector:String, listenerFirstClick:MouseEvent->Void, listenerSecondClick:MouseEvent->Void):DOMNode
	{
		// Declare and initialise now so they can reference each other in their function bodies.
		var fn1:MouseEvent->Void = null;
		var fn2:MouseEvent->Void = null;

		// Wrap the first click function to run once, then remove itself and add the second click function
		fn1 = function (e:MouseEvent)
		{
			listenerFirstClick(e);
			off(target, "click", untyped fn1);
			on(target, "click", selector, untyped fn2);
		}

		// Wrap the second click function to run once, then remove itself and add the first click function
		fn2 = function (e:MouseEvent)
		{
			listenerSecondClick(e);
			off(target, "click", untyped fn2);
			on(target, "click", selector, untyped fn1);
		}

		// Add the first one to begin with
		on(target, "click", selector, untyped fn1);

		return target;
	}

	public static inline function blur(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "blur", selector, listener);
	}

	public static inline function change(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "change", selector, listener);
	}

	public static inline function click(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "click", selector, listener);
	}

	public static inline function dblclick(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "dblclick", selector, listener);
	}

	public static inline function focus(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "focus", selector, listener);
	}

	public static inline function focusIn(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "focusIn", selector, listener);
	}

	public static inline function focusOut(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "focusOut", selector, listener);
	}

	public static inline function resize(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "resize", selector, listener);
	}

	public static inline function scroll(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "scroll", selector, listener);
	}

	public static function wheel(target:DOMNode, ?selector:String, ?listener:js.html.WheelEvent->Void):DOMNode
	{
		// Just use the HTML5 standard for now.  Works in IE9+ and FF17+, probably not webkit/opera yet.
		target.addEventListener("wheel", untyped listener);
		return target;
		
		// Later, we can try implement this, which has good fallbacks
		// https://developer.mozilla.org/en-US/docs/Mozilla_event_reference/wheel?redirectlocale=en-US&redirectslug=DOM%2FDOM_event_reference%2Fwheel
	}

	public static inline function select(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "select", selector, listener);
	}

	public static inline function load(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "load", selector, listener);
	}

	public static inline function unload(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "unload", selector, listener);
	}

	public static inline function error(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "error", selector, listener);
	}

	public static inline function ready(target:DOMNode, ?selector:String, ?listener:EventListener):DOMNode
	{
		return on(target, "ready", selector, listener);
	}

}