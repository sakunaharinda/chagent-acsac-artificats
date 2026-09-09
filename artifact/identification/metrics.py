import numpy as np
from evaluate import load
 
def compute_metrics(eval_pred):
   load_accuracy = load("accuracy")
   load_f1 = load("f1")
   load_p = load("precision")
   load_r = load("recall")
  
   logits, labels = eval_pred
   predictions = np.argmax(logits, axis=-1)
   accuracy = load_accuracy.compute(predictions=predictions, references=labels)["accuracy"]
   f1 = load_f1.compute(predictions=predictions, references=labels)["f1"]
   p = load_p.compute(predictions=predictions, references=labels)["precision"]
   r = load_r.compute(predictions=predictions, references=labels)["recall"]
   return {"accuracy": accuracy, "f1": f1, "precision": p, "recall": r}


# import numpy as np
# from evaluate import load
 
# def compute_metrics(eval_pred):
#    load_accuracy = load("accuracy")
#    load_f1 = load("f1")
  
#    logits, labels = eval_pred
#    predictions = np.argmax(logits, axis=-1)
#    accuracy = load_accuracy.compute(predictions=predictions, references=labels)["accuracy"]
#    f1 = load_f1.compute(predictions=predictions, references=labels)["f1"]
#    return {"accuracy": accuracy, "f1": f1}