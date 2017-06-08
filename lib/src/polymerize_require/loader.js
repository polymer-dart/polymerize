define([], function() {

	let onModLoad = function(config, name, onload) {
		return function(mod) {
			console.log('loaded mod ' + name);
			let pars = config.polymerize_init && config.polymerize_init[name];
			if (pars) {
				console.log('running init with ' + pars);
				mod[pars[0]][pars[1]]();
			}
			onload(mod);
		};
	};

	return {
		load: function(name, parentRequire, onload, config) {
			console.log('loading ' + name + ' with polymerize and config');
			// Remove mapping for this mod
			delete config.map['*'][name];

			let finish = function() {
				require(config,[name], onModLoad(config, name, onload));
			};

			if (config.polymerize_loader && config.polymerize_loader[name]) {
				console.log('loading with -> ' + config.polymerize_loader[name]);
				parentRequire(config.polymerize_loader[name], function() {
					console.log('loaded deps for' + name);
					finish();
				});
			} else {
				console.log('loading with no deps ');
				finish();
			}

		}


	};
});
