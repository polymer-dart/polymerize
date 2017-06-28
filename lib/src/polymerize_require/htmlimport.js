define([], function() {
  return {
    load: function(name, parentRequire, onload, config) {
      let link = document.createElement('link');
      link.rel = 'import';
      link.href = name;
      link.onload = (ev) => {
        //console.log('loaded '+name);
        onload(ev);
      }
      document.head.append(link);
    }
  }
});
