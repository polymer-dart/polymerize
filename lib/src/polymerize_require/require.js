function polymerize_redefine(polymerize_loader,polymerize_init) {

	var oldDefine = define;
	define = function(name,deps,callback) {
		var id = document.currentScript.getAttribute('data-requiremodule');
		// console.log("DEFINING : "+id);
		let d=deps;
		let cb = callback;
		if (typeof name!=='string') {
			d = name;
			cb = deps;
		} 
		// Append extra deps
		if (polymerize_loader[id]) {
			Array.prototype.push.apply(d,polymerize_loader[id]);
		}
		
		let newCb = cb;
		if (polymerize_init[id]) {
		  newCb = function() {
		    let mod = cb.apply(null,Array.prototype.slice.call(arguments));
		    mod[polymerize_init[id][0]][polymerize_init[id][1]]();
		    return mod;
		  }
		}
		if (typeof name!=='string') {
			name = d;	
			deps = newCb;
		} else {
			deps = d;
			callback = newCb;
		}
		return oldDefine(name,deps,callback);
	};
	
	define.amd = true;
}
            
