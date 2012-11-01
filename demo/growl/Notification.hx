using Detox;
using StringTools;

@template("<div class='notification alert fade in out'>
	<a class='close' href='#'>&times;</a>
	<h4 class='alert-heading'>Title</h4>
	<p>Description goes here</p>
</div>")
class Notification extends dtx.widget.Widget
{
	public function new(title:String, comment:String)
	{
		super();

		// Set the title and the comment
		this.find("h4").setText(title);
		this.find("p").setInnerHTML(comment.replace('\n', '\n<br />'));

		// Set up the event to close the notification
		this.find('.close').click(function (e) {
			trace ("remove");
			this.remove();
		});
	}


}