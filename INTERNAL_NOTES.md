# Annotazioni

Devcompiler traduce tutte le classi annotate con `@Native` ed i metodi annotati con `@Native` usando simboli al posto del nome.

Queste classi vengono usate da `registerExtension` in pratica copiando tutti i simboli dalla classe generata alla classe JS. Questo viene fatto rispettando la gerarchia
dei `__proto__`. 

Quando un elemento di questo tipo deve essere trasformato in dart viene di fatto lasciato così com'è (da capire meglio).


