const Analyzer = require('polymer-analyzer').Analyzer;
const FSUrlLoader = require('polymer-analyzer/lib/url-loader/fs-url-loader').FSUrlLoader;
const PackageUrlResolver = require(
  'polymer-analyzer/lib/url-loader/package-url-resolver').PackageUrlResolver;

let hyd = new Analyzer({
  urlLoader: new FSUrlLoader(process.argv[2]
    /*"/home/vittorio/Develop/dart/polymer_element/lib/src"*/
  ),
  urlResolver: new PackageUrlResolver(),
});
/*
analyzer.analyze('/paper-button/paper-button.html')
  .then((document) => {
    document.getById('polymer-element', 'paper-button').forEach(function(x) {
      x.properties.forEach(function(p) {
        console.log(p);

      });
      //console.log(JSON.stringify(x));
    });;
  });

*/
var filePath = process.argv[3];


try {
  ///console.log("***READING " + process.argv[3] + " from " + process.argv[2]);
  hyd.analyze(filePath)
    .then(function(results) {
      //console.log("***READ");
      //console.dir(results);
      console.log(JSON.stringify({
        /*imports: results.html[filePath].depHrefs,*/
        elements: getElements(results, filePath),
        behaviors: getBehaviors(results, filePath),
        path: filePath
      }));
    });
} catch (e) {
  console.log(e);
}

function getElements(results, filePath) {
  var elements = {};
  var polymer_elements = results.getByKind('polymer-element');
  if (!polymer_elements) return elements;
  //console.log("*** FOUND " + polymer_elements.size + " elements");

  polymer_elements.forEach(function(element) {
    //if (element.sourceRange.file != filePath) return;
    //console.dir(element);
    var className = element.className || toCamelCase(element.tagName);
    //console.log("*** ELE " + className);
    if (elements[className]) return;
    /*
        element.attributes.forEach(function(a) {
          console.log(a);
        });
    */
    elements[className] = {
      extendsName: getExtendsName(element),
      name: element.tagName,
      properties: getProperties(element),
      methods: getMethods(element),
      description: element.description,
      behaviors: element.behaviorAssignments || [],
      main_file: element.sourceRange.file == filePath,
      src: element.sourceRange.file
    };
  });
  return elements;
}

function getBehaviors(results, filePath) {
  var behaviors = {};
  var polymer_behaviors = results.getByKind('behavior');
  if (!polymer_behaviors) return behaviors;
  ///console.log("*** FOUND " + polymer_behaviors.size + " behaviors");
  polymer_behaviors.forEach(function(behavior) {
    //if (behavior.sourceRange.file != filePath) return;
    ///console.dir(behavior);
    var name = behavior.className; //.replace('Polymer.', '');
    if (behaviors[name]) return;

    behaviors[name] = {
      name: name,
      properties: getProperties(behavior),
      methods: getMethods(behavior),
      description: behavior.description,
      behaviors: behavior.behaviorAssignments,
      main_file: behavior.sourceRange.file == filePath,
      src: behavior.sourceRange.file
    };
  });
  return behaviors;
}

function getProperties(element) {
  var properties = {};
  if (!element.properties) return properties;
  for (var i = 0; i < element.properties.length; i++) {
    var property = element.properties[i];
    if (!property.published) continue;
    if (isPrivate(property) || !isField(property)) continue;
    if (property.inheritedFrom) continue;
    //if (property.name == 'extends') continue;
    if (properties[property.name]) continue;
    //console.log("*** CIP " + property + " " + property.astNode);
    if (property.astNode.value.type != 'ObjectExpression') continue;
    //console.dir(property);
    properties[property.name] = {
      hasGetter:
        !property.function || isGetter(property) ||
        (isSetter(property) && hasPropertyGetter(element, property.name)),
      hasSetter: !property.readOnly && (!property.function || isSetter(
          property) ||
        (isGetter(property) && hasPropertySetter(element, property.name))),
      name: property.name,
      type: getFieldType(property),
      description: property.description || ''
    };
  }
  return properties;
}

function getFieldType(property) {
  if (isGetter(property)) return property.return ? property.return.type :
    null;
  if (isSetter(property)) return property.params[0].type;
  return property.type;
}

function getMethods(element) {
  var methods = {};
  if (!element.properties) return methods;
  for (var i = 0; i < element.properties.length; i++) {
    var property = element.properties[i];
    if (property.inheritedFrom) continue;
    if (isPrivate(property) || !isMethod(property)) continue;
    if (methods[property.name]) continue;

    methods[property.name] = {
      name: property.name,
      type: property.return ? property.return.type : null,
      description: property.description || '',
      isVoid: !property.return,
      args: getArguments(property)
    };
  }
  return methods;
}

function getArguments(func) {
  var args = [];
  if (!func.params) return args;
  for (var i = 0; i < func.params.length; i++) {
    var param = func.params[i];
    args.push({
      name: param.name,
      description: param.desc || '',
      type: param.type
    });
  }
  return args;
}

function getExtendsName(element) {
  return element.extends;
  /*
  if (!element.properties) return null;
  for (var i = 0; i < element.properties.length; i++) {
    var prop = element.properties[i];
    if (prop.name == 'extends') {
      return prop.javascriptNode.value.value;
    }
  }*/
}

function isPrivate(property) {
  return property.private || property.name.length > 0 && property.name[0] ==
    '_';
}

function isMethod(property) {
  if (property.type != 'Function') return false;
  return !isGetter(property) && !isSetter(property);
}

function isField(property) {
  if (!property.function) return true;
  return isGetter(property) || isSetter(property);
}

function isGetter(field) {
  if (!field.function) return false;
  return field.getter; //field.astNode.kind == 'get';
}

function isSetter(field) {
  if (!field.function) return false;
  return field.setter; // field.astNode.kind == 'set';
}

function hasPropertySetter(element, name) {
  for (var i = 0; i < element.properties.length; i++) {
    var prop = element.properties[i];
    if (prop.name == name && prop.function && prop.astNode.kind ==
      'set')
      return true;
  }
  return false;
}

function hasPropertyGetter(element, name) {
  for (var i = 0; i < element.properties.length; i++) {
    var prop = element.properties[i];
    if (prop.name == name && prop.function && prop.astNode.kind ==
      'get')
      return true;
  }
  return false;
}

function toCamelCase(dashName) {
  return dashName.split('-').map(function(e) {
    return e.substring(0, 1).toUpperCase() + e.substring(1);
  }).join('');
}
