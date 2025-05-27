local preproc = require "preprocessor";

preproc.enableDebug();

preproc.optimization(2);

preproc.define("__HOST__");

preproc.excludeScript("preprocessor");
preproc.excludeScript("reader");

preproc.addAutoscript("test")

preproc.runAfterPreprocess()

preproc.run();
