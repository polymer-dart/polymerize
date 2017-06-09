define([], function () {

    let onModLoad = function (config, name, onload) {
        return function (mod) {
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
        load: function (name, parentRequire, onload, config) {
            console.log('loading ' + name + ' with polymerize and config');

            delete config.map['*'][name];

            require(config, [name], onModLoad(config, name, onload));


        }


    };
});
