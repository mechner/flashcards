import java.util.Random; 
import java.util.Deque;
import java.util.ArrayDeque;
import java.util.Date; 
import java.text.SimpleDateFormat; 
import processing.sound.*;

enum Operator { ADD, MULT }
enum State { TITLE, PROBLEM, TEACH, ADVANCE, END }
enum ProblemType { REVIEW, WORK }


final int WORKSET_SIZE = 100; // how many problems in a workset
final int AVG_TIME_REQUIRED_TO_ADVANCE_MS = 5000; // only allow advance if avg. problem time <= this (note max counted for each problem is 6000)


Random rand = new Random(); 

ProblemGenerator generator; 
Problem problem; 
Tracker tracker; 
Table records; 
State state = State.TITLE; 
long stateStartTime; 
long problemStartTime; 
long sessionStartTime; 
long lastReminderTime; 


PFont probFont, guessFont, scoreFont, msgFont; 
SoundFile successSound, missSound, advanceSound;
Env reminderEnvelope;
SinOsc sineWave; 
int margin; 

/**
 * General program scheme: 
 * 
 * There are 5 states (controlled by the global state variable): 
 * - TITLE - waiting for a session to start (on mouse click -> PROBLEM)
 * - PROBLEM - displaying a problem, waiting for response (on mouse click -> PROBLEM (if correct) or TEACH (of wrong))
 * - TEACH - displaying the correct answer after a wrong response (after timer -> PROBLEM)
 * - ADVANCE - displaying the congratulation when moving to the next working number (see tryAdvance()) (on timer -> PROBLEM)
 * - END - displaying the contratulation after completing the session (on timer -> TITLE - another set will start) 
 * From any state, pressing a number key will go -> TITLE (starting a new session with the given working number)
 * To understand the program, review all the places where state is set or checked.  
 */

void setup() {
  size(640, 360);
  margin = width / 10; 
  probFont = createFont("Helvetica", 96);
  guessFont = createFont("Helvetica", 72);
  scoreFont = createFont("Helvetica", 12); 
  msgFont = createFont("Helvetica", 36); 
  successSound = new SoundFile(this, "success.mp3");
  missSound = new SoundFile(this, "miss.wav");
  advanceSound = new SoundFile(this, "advance.mp3"); 
  reminderEnvelope  = new Env(this); 
  sineWave = new SinOsc(this); 
  generator = new ProblemGenerator();  
  records = loadRecords(); 
  int start_n = 3; 
  try {
    System.out.println("Loaded data records file with " + records.getRowCount() + "records."); 
    TableRow r = records.getRow(records.getRowCount()-1);
    start_n = r.getInt("end_n"); 
  } catch (Exception e) { e.printStackTrace(); }
  tracker = new Tracker(start_n, WORKSET_SIZE);
}


void draw() {
  background(100); 
  if (state == State.PROBLEM) {
    problem.display(State.PROBLEM); 
    displayTracker();
    remind(); 
  }
  else if (state == State.TEACH) {
    problem.display(state); 
    displayTracker();
    if (millis() - stateStartTime > 3000) {
       // Note - we purposely don't change the problem so they can immediately practice what they just missed
       state = State.PROBLEM; 
       problemStartTime = millis(); 
       stateStartTime = problemStartTime; 
    }
  }
  else if (state == State.ADVANCE) {
     displayAdvance();  
     if (millis() - stateStartTime > 5000) {
       state = State.PROBLEM; 
       problem = generator.generateProblem(tracker.getN()); 
       problemStartTime = millis(); 
       stateStartTime = problemStartTime; 
     }
  }
  else if (state == State.TITLE) {
    displayTitle(); 
  }
  else if (state == State.END) {
    displayEnd();
    if (millis() - stateStartTime > 5000) {
      tracker = new Tracker(tracker.getN(), WORKSET_SIZE); 
      state = State.TITLE;  
    }
  }
}


void mouseClicked() {
  if (state == State.TITLE) {
    state = State.PROBLEM; 
    tracker = new Tracker(tracker==null? 3 : tracker.getN(), WORKSET_SIZE);
    problem = generator.generateProblem(tracker.getN());
    problemStartTime = millis(); 
    sessionStartTime = problemStartTime; 
    stateStartTime = problemStartTime; 
    return;
  }
  else if (state == State.PROBLEM) {
    int ans = problem.getAnswer(); 
    if (ans >= 0) {
       int elapsed = (int) (millis() - problemStartTime); 
       if (ans == problem.answer) {
         // CORRECT
         tracker.addResult(1, elapsed, problem.type); 
         successSound.play();
         if (tracker.isDone()) {
           state = State.END;
           advanceSound.play(); 
           saveRecord(records, tracker); 
           stateStartTime = millis(); 
         }
         else if (tracker.tryAdvance()) {
            state = State.ADVANCE;
            stateStartTime = millis(); 
            advanceSound.play(); 
         }
         else {
           problem = generator.generateProblem(tracker.getN());
           state = State.PROBLEM; 
           problemStartTime = millis(); 
           stateStartTime = problemStartTime; 
         }
       }
       else {
         // INCORRECT
         tracker.addResult(0, elapsed, problem.type); 
         state = State.TEACH; 
         stateStartTime = millis(); 
         missSound.play();         
       }
    }
  }
}

/**
 * At any time the user can re-start from a particular number between 3 and 9 by pressing a number key. 
 */
void keyPressed() {
  if (Character.isDigit(key)) {
    state = State.TITLE;
    tracker.setN(Math.max(3, Character.getNumericValue(key)));
  }
}


void displayTracker() {
  float x = height * .05; 
  float y = height * .95; 
  textFont(scoreFont);
  boolean showDetails = true; // keyPressed && key == ' '; 
  text(tracker.summary(showDetails), x, y); 
}

void displayTitle() {
   background(200);
   fill(50);
   textFont(guessFont);
   textAlign(LEFT, TOP);
   String msg = "Goal: " + tracker.totalCorrectRequired + " correct\n" + 
     "Starting with " + tracker.getN() + "'s\n" + 
     "Click to start."; 
   text(msg, width * .05, height*.1);     
}

void displayAdvance() {
   background(100);
   fill(30, 255, 30);
   textFont(guessFont);
   textAlign(LEFT, TOP);
   String msg = "Congratulations!\nAdvancing to " + tracker.getN() + "'s!"; 
   text(msg, width * .1, height*.25);     
}

void displayEnd() {
   background(200);
   fill(50);
   textFont(msgFont);
   textAlign(LEFT, TOP);
   String msg = "Done!\nYou got " + tracker.getPctRight() + "% RIght."; 
   text(msg, width * .05, height*.1);
}


/**
 * If 15 seconds goes by without a response, play a reminder sound in case the student has gotten distracted, 
 * and repeat the sound every 3 seconds thereafter. 
 */
void remind() {
  long t = millis(); 
  if ((t - problemStartTime > 15000) && (t - lastReminderTime > 5000)) {
     reminderEnvelope.play(sineWave, .1, .5, 1.5, .1); // args: attackTime, sustainTime, sustainLevel, releaseTime
     lastReminderTime = t;
  }
}


/** Appends a record row to the record file, CSV. */
Table loadRecords() {
  Table t; 
  try {
     t = loadTable("data/record.csv", "header"); 
  }
  catch (Exception e) {
    println("Couldn't load data/record.csv; creating new record file.");
    t = new Table(); 
    t.addColumn("date"); 
    t.addColumn("time"); 
    t.addColumn("dur_mins"); 
    t.addColumn("n_correct"); 
    t.addColumn("n_total"); 
    t.addColumn("pct_correct"); 
    t.addColumn("start_n");
    t.addColumn("end_n"); 
    saveTable(t, "data/record.csv");
  }
  return t;
}

void saveRecord(Table records, Tracker tracker) {
  TableRow r = records.addRow();
  r.setString("date", new SimpleDateFormat("yyyy-MM-dd").format(new Date()));
  r.setString("time", new SimpleDateFormat("HH:mm:ss").format(new Date()));
  r.setFloat("dur_mins", (millis()-tracker.getSessionStart())/60000.0);
  r.setInt("n_correct", tracker.totalCorrect);
  r.setInt("n_total", tracker.totalAttempted); 
  r.setInt("pct_correct", tracker.getPctRight()); 
  r.setInt("start_n", tracker.startingN);
  r.setInt("end_n", tracker.n);
  saveTable(records, "data/record.csv"); 
}


/**
 * Generates multiplication problems, including picking good distractors. 
 * Stateless. 
 */ 
class ProblemGenerator {
  
  /** Generates either a PRACTIUCE or WORK problem (50/50). */
  Problem generateProblem(int n) {
     if (random(1) < .5) 
       return generateReviewProblem(n); 
     else 
       return generateWorkProblem(n);  
  }
  
  /** Generate PRACTICE problem up to but excluding n as a factor. */
  private Problem generateReviewProblem(int n) {
    int a = rand.nextInt(n-1)+1; 
    int b = rand.nextInt(n-1)+1; 
    if (a == b && random(1) < 0.5) // don't over-represent n * n; half the time pick again if they're equal
      return generateReviewProblem(n); 
    return new Problem(a, b, Operator.MULT, a*b, getOptions(a, b), ProblemType.REVIEW); 
  }
  
  /** Generate WORK problem with n as one factor (and the other in 1..n). */
  private Problem generateWorkProblem(int n) {
    int a, b; 
    a = n; 
    b = rand.nextInt(n)+1; 
    if (random(1) < .5) {
      int tmp = a; 
      a = b; 
      b = tmp; 
    }
    return new Problem(a, b, Operator.MULT, a*b, getOptions(a, b), ProblemType.WORK);     
  }
  
  private int[] getOptions(int a, int b) {
    if (a==b)
      return getOptionsForAA(a); 
    final int N = 3; 
    IntList opts = new IntList(); 
    int answerPos = rand.nextInt(N); 
    switch (answerPos) {
      case 0: 
        opts.append(a * b); 
        opts.append(a * (b+1));
        opts.append((a+1) * b); 
        break; 
       case 1: 
         opts.append(random(1) < .5 ? (a-1) * b : a * (b-1)); 
         opts.append(a * b); 
         opts.append(random(1) < .5 ? (a+1) * b : a * (b+1)); 
         break; 
       case 2: 
         opts.append((a-1) * b); 
         opts.append(a * (b-1));
         opts.append(a * b); 
         break;        
    }
    opts.sort(); 
    return opts.array(); 
  }
  
  private int[] getOptionsForAA(int a) {
    final int N = 3; 
    int[] options = new int[N];
    int answerPos = rand.nextInt(N); 
    switch (answerPos) {
      case 0: 
        options[0] = a * a; 
        options[1] = a * (a+1);
        options[2] = a * (a+2); 
        break; 
       case 1: 
         options[0] = a * (a-1); 
         options[1] = a * a; 
         options[2] = a * (a+1);  
         break; 
       case 2: 
         if (a==1) return new int[] {0, 1, 2}; // special case for 1*1 since there are no 2 distractors < 1
         options[0] = a * (a-2); 
         options[1] = a * (a-1); 
         options[2] = a * a; 
         break;        
    }
    return options; 
  }
}


/** 
 * Represents a rectangle for the clickable options for click detection. 
 */ 
class Rect {
   public float x, x2; 
   public float y, y2; 

   Rect(float x, float y, float ht, float wd) {
      this.x = x; 
      this.x2 = x + ht; 
      this.y = y; 
      this.y2 = y + wd; 
   }
   
   boolean mouseInside() {
     return mouseX >= x && mouseX <= x2 && mouseY >= y && mouseY <= y2;
   }
}


/**
 * Represents a problem (including the operands, answer, and the options to click on). 
 * Encapsulates display and determining which option the user has guessed. 
 */
class Problem {
  int a, b, answer; 
  Operator op; 
  int[] options; 
  Rect[] guessRects; 
  ProblemType type; 
 
  Problem(int a, int b, Operator op, int answer, int[] options, ProblemType type) {
    this.a = a; 
    this.b = b; 
    this.op = op; 
    this.answer = answer; 
    this.options = options; 
    this.guessRects = new Rect[options.length];
    this.type = type; 
    
    // Calculate and cache guess rects
    textFont(guessFont); 
    float u = width/10; 
    float y = height - 2*u; 
    float ht = 60;
    for (int i=0; i<options.length; i++) {
      String guessText = Integer.toString(options[i]);
      float x = ((i * 3) + 1) * u; 
      float wd = textWidth(guessText);
      guessRects[i] = new Rect(x, y, wd, ht); 
    }
  }
  
  String opString() {
    return " \u00d7 ";
  }
  
  // returns the answer if the mouse is over an asnwer else -1
  int getAnswer() {
    for (int i=0; i<options.length; i++) {
      if (guessRects[i].mouseInside())
        return options[i]; 
    }
    return -1; 
  }
  
  void display(State state) {
    fill(230);
    textFont(probFont);
    textAlign(LEFT, TOP);
    String problem = a + opString() + b + " = "; 
    if (state == State.TEACH)
      problem += answer; 
    text(problem, margin, margin-10); 
    
    if (state == State.PROBLEM) {
      textFont(guessFont); 
      for (int i=0; i<options.length; i++) {
         fill(getAnswer() == options[i] ? 255 : 220);
         String answerText = Integer.toString(options[i]);
         Rect r = guessRects[i]; 
         text(answerText, r.x, r.y);
      }
    }
  }  
}


/**
 * Tracks progress, time and performance in the current working set.
 */
class Tracker {
   static final float WORK_FACTOR = 2; // times n - how many work problems we have to do (there are n*2-1)
   static final float REVIEW_FACTOR = .5; // times n^2 - how many review problems we have to do
   static final int MAX_TIME = 6000; // we cap the time spent on an individual probem at 5s so distractions or pauses don't make the average garbage
   
   int n; // the highest number our problems include - the "working" number
   Series review; // FILO queue of "recent history" for review problem performance
   Series working; // " for working problem performance
   int totalCorrect = 0; 
   int totalAttempted = 0; 
   int totalCorrectRequired = 100; 
   long sessionStart; 
   int startingN; 
   
   Tracker(int highest, int totalReqd) {
     this.n = highest; 
     this.startingN = highest; 
     this.totalCorrectRequired = totalReqd;
     review = new Series(0); 
     working = new Series(0); 
     setN(n); 
     sessionStart = millis(); 
   }
   
   int getN() {
     return n;
   }
   
   long getSessionStart() {
     return sessionStart; 
   }
   
   int getPctRight() {
     return (int) (100 * totalCorrect / (float)totalAttempted);
   }

   void setN(int n) {
     this.n = n; 
     review.setN((int)Math.ceil(n*n*REVIEW_FACTOR)); 
     working.setN((int)Math.ceil(n*WORK_FACTOR)); 
     working.clear(); 
   }
   
    void addResult(int res, int time, ProblemType type) {
      totalCorrect += res; 
      totalAttempted++;
      if (type == ProblemType.REVIEW)
        review.addResult(res, Math.min(MAX_TIME, time)); 
      else
        working.addResult(res, Math.min(MAX_TIME, time)); 
   }
   
   String summary(boolean showDetails) {
     String msg = "You got " + totalCorrect + " / " + totalCorrectRequired + " at " + getPctRight() + "%"; 
     if (showDetails) 
       msg += "    Review: " + review.summary() + " | Work(" + n + "): " + working.summary();
     return msg; 
   }
   
   boolean tryAdvance() {
     if (review.isFull() && working.isFull() && 
         review.getPctRight() > 95 && working.getPctRight() > 95 && 
         review.getAvgSolveTimeMs() <= AVG_TIME_REQUIRED_TO_ADVANCE_MS && 
         working.getAvgSolveTimeMs() <= AVG_TIME_REQUIRED_TO_ADVANCE_MS
       ) {
       setN(n+1);  
       return true; 
     }
     return false; 
   }
   
   boolean isDone() {
     return totalCorrect >= totalCorrectRequired && getPctRight() > 80; 
   }
}


/**
 * Tracks the trailing N responses' correctness and response time.
 * Convenience methods for getting percent correct and avg response time. 
 */
class Series {
   int n;
   Deque<Integer> results;
   Deque<Integer> times; 
   
   Series(int n) {
     this.n = n;  
     results = new ArrayDeque<Integer>(); 
     times = new ArrayDeque<Integer>(); 
   }

   void setN(int n) {
     this.n = n; 
     while(results.size() >= n) {
       results.removeFirst(); 
       times.removeFirst(); 
     }       
   }
   
   void clear() {
     results.clear(); 
     times.clear(); 
   }
   
   void addResult(int res, int time) {
     if (results.size() == n) {
       results.removeFirst(); 
       times.removeFirst();
     }
     results.addLast(res); 
     times.addLast(time);
   }
   
   boolean isFull() {
     return results.size() >= n;  
   }
   
   String summary() {
     int s = sum(results); 
     if (results.size() == 0) 
       return ""; 
     else
       return s + " / " + results.size() + " (" + getPctRight() + "%) rt " + (int)(sum(times)/times.size());
   }
      
   int sum(Deque<Integer> array) {
     int s = 0; 
     for (int i : array)
       s += i; 
     return s; 
   }
      
   int getPctRight() {
     return (int) (100 * sum(results) / (float)results.size());
   }
   
   int getAvgSolveTimeMs() {
     return (int) (sum(times) / (float)times.size()); 
   }
}
