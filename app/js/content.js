// Static program content: ISI items, lessons, night-mode scripts, word lists.

// Insomnia Severity Index © Charles M. Morin. Included for personal, non-commercial self-monitoring.
export const ISI = [
  { q: 'Difficulty falling asleep (last 2 weeks)', a: ['None', 'Mild', 'Moderate', 'Severe', 'Very severe'] },
  { q: 'Difficulty staying asleep (last 2 weeks)', a: ['None', 'Mild', 'Moderate', 'Severe', 'Very severe'] },
  { q: 'Problems waking up too early (last 2 weeks)', a: ['None', 'Mild', 'Moderate', 'Severe', 'Very severe'] },
  {
    q: 'How satisfied / dissatisfied are you with your current sleep pattern?',
    a: ['Very satisfied', 'Satisfied', 'Moderately satisfied', 'Dissatisfied', 'Very dissatisfied'],
  },
  {
    q: 'How noticeable to others do you think your sleep problem is in terms of impairing your quality of life?',
    a: ['Not at all', 'A little', 'Somewhat', 'Much', 'Very much'],
  },
  {
    q: 'How worried / distressed are you about your current sleep problem?',
    a: ['Not at all', 'A little', 'Somewhat', 'Much', 'Very much'],
  },
  {
    q: 'To what extent does your sleep problem interfere with your daily functioning (fatigue, mood, concentration, memory, work/study)?',
    a: ['Not at all', 'A little', 'Somewhat', 'Much', 'Very much'],
  },
];

export const RED_FLAGS = [
  'Loud snoring, or someone has seen you stop breathing / gasp in your sleep',
  'An urge to move your legs in the evening with crawling/creeping feelings that ease when you move',
  'Falling asleep without meaning to during the day (in class, talking, driving)',
  'Bipolar disorder, epilepsy / seizures, or currently pregnant',
  'Low mood most days, or thoughts of harming yourself',
];

// Week focus: shown on Today. Lessons are all available; these are highlighted per week.
export const WEEK_FOCUS = {
  0: { title: 'Baseline week', lessons: ['how-sleep-works', 'anchor'], tasks: ['Log the diary every morning', 'Same wake time every day', 'Outdoor light within 30 min of waking', 'Podcast moves to the chair, not the bed'] },
  1: { title: 'Your sleep window', lessons: ['window', 'bed-rules'], tasks: ['Bed only when sleepy, and not before your window opens', 'Up at your anchor, no matter how the night went', 'No naps'] },
  2: { title: 'Quiet the mind', lessons: ['quiet-mind'], tasks: ['Worry Time every evening', 'To-do offload before wind-down', 'Cognitive shuffle if thoughts race in bed'] },
  3: { title: 'Calm the body', lessons: ['calm-body'], tasks: ['Practise muscle relaxation in the evening (not just at 2 am)', 'Slow breathing during wind-down'] },
  4: { title: 'Sleep beliefs', lessons: ['beliefs', 'paradox'], tasks: ['Catch one unhelpful sleep thought a day and reframe it', 'Try "staying awake" on 3 nights'] },
  5: { title: 'Fine-tune', lessons: ['experiments'], tasks: ['Run one experiment (e.g. no podcast in bed for 5 nights)'] },
  6: { title: 'Relapse-proof', lessons: ['relapse'], tasks: ['Write your one-line sleep plan', 'Keep the anchor and the diary 3×/week'] },
};

export const LESSONS = [
  {
    id: 'how-sleep-works',
    title: 'How sleep actually works',
    mins: 2,
    body: `
<p>Two systems decide when you fall asleep:</p>
<ul>
<li><b>Sleep drive</b> builds the longer you're awake, like hunger. Naps, sleep-ins and long hours in bed all drain it.</li>
<li><b>The body clock</b> sets <i>when</i> you feel alert or sleepy. It's set mostly by <b>when you wake up and when you see light</b>.</li>
</ul>
<p>When both line up at bedtime, sleep comes easily. Insomnia usually means they've drifted apart, and on top of that the bed has become a place where your brain practises being awake.</p>
<p>Nothing is broken. The program re-lines these systems up and retrains the bed.</p>`,
  },
  {
    id: 'anchor',
    title: 'The wake anchor & morning light',
    mins: 2,
    body: `
<p>Your <b>wake anchor</b> is one fixed time you get out of bed <b>every day, weekends included</b>, no matter how badly you slept.</p>
<p>Why it matters:</p>
<ul>
<li>It sets your body clock, and your bedtime sleepiness follows it about 16 hours later.</li>
<li>After a bad night, getting up on time builds sleep drive for the next night. Sleeping in steals it.</li>
<li>Irregular sleep timing predicts worse health outcomes even more strongly than short sleep does.</li>
</ul>
<p><b>Light:</b> get outside within 30 minutes of waking for 10–30 min. Even an overcast sky is far brighter than indoor light. Keep evenings dim.</p>`,
  },
  {
    id: 'window',
    title: 'Why less time in bed means more sleep',
    mins: 3,
    body: `
<p>If you're in bed 8½ hours but sleeping 6, your brain is learning to sleep lightly and in pieces. The <b>sleep window</b> shrinks time in bed to about what you actually sleep, then grows it back as sleep gets solid.</p>
<ul>
<li>Your window = your average sleep from the baseline week (never under 5 hours).</li>
<li>Bedtime = wake anchor − window. <b>Don't go to bed before the window opens</b>, even if you're tired.</li>
<li>Each week the app checks your <b>sleep efficiency</b> (time asleep ÷ time in bed). At 90% or above you get +15 min. Below 85% the window tightens. In between, it holds.</li>
</ul>
<p><b>Weeks 1–2 are the hardest.</b> You'll be sleepier during the day. That's the treatment working. <b>Don't drive when drowsy.</b></p>
<p>This is the single most effective part of CBT-I, and it only works if you actually stick to the window.</p>`,
  },
  {
    id: 'bed-rules',
    title: 'The bed rules (stimulus control)',
    mins: 2,
    body: `
<ol>
<li><b>Go to bed only when sleepy</b>, meaning eyes heavy and head nodding, not just tired. If that's after your window opens, that's fine.</li>
<li><b>Bed is for sleep</b> (and sex). No podcasts, scrolling, study or planning in bed.</li>
<li>If you feel you've been awake <b>about 15–20 minutes</b> (guess; <b>don't check the clock</b>), <b>get up</b>. Go somewhere dim, do something calm and boring, and come back when sleepy. Repeat as often as needed.</li>
<li><b>Get up at your wake anchor</b>, every day.</li>
<li><b>No naps.</b></li>
</ol>
<p>The goal is for your brain to relearn <i>bed = falling asleep quickly</i>. It's annoying for a week or two and then it starts working.</p>
<p>About the podcast: listening in the chair during wind-down is great. An hour of it in bed teaches your brain that bed is for being awake.</p>`,
  },
  {
    id: 'quiet-mind',
    title: 'Quieting a racing mind',
    mins: 3,
    body: `
<p>Thoughts race in bed because it's the first quiet moment of the day. The fix is to deal with them <b>earlier</b> and somewhere else.</p>
<ul>
<li><b>Worry Time</b> (about 3 h before bed, out of the bedroom, 15 min): write each worry and one next step, even if the step is "nothing I can do tonight". Then close the book. If a worry shows up in bed, tell yourself "it's in the book".</li>
<li><b>To-do offload</b> (5 min, during wind-down): write a <b>specific</b> to-do list for the next few days. In a study it got people to sleep about 9 minutes faster, and the more specific the list, the bigger the effect.</li>
<li><b>Cognitive shuffle</b> (in bed): pick a random word and, for each letter, picture random unrelated things starting with it. It mimics the drifting, nonsense thinking of falling asleep. It's in Night Mode.</li>
</ul>`,
  },
  {
    id: 'calm-body',
    title: 'Calming a restless body',
    mins: 2,
    body: `
<p>A wired, restless body is a raised arousal level, not a lack of tiredness.</p>
<ul>
<li><b>Progressive muscle relaxation (PMR)</b> means tensing each muscle group for about 5 seconds, then releasing it for 15. It's one of the best-tested relaxation methods for insomnia. <b>Practise it in the evening</b> so it works when you need it at 2 am.</li>
<li><b>Slow breathing</b>: about 6 breaths a minute (in 4s, out 6s). A long out-breath slows the heart.</li>
</ul>
<p>Both are in Night Mode.</p>`,
  },
  {
    id: 'beliefs',
    title: 'Sleep thoughts that keep you awake',
    mins: 3,
    body: `
<p>Anxiety about sleep is fuel for insomnia. Some common thoughts, and more accurate versions:</p>
<ul>
<li><i>"If I don't get 8 hours I'll be useless tomorrow."</i> → You've had many bad nights and still functioned, maybe not perfectly. One night barely changes performance; your brain makes up for it with deeper sleep next time.</li>
<li><i>"I've lost the ability to sleep."</i> → Sleep is automatic. It's being blocked by arousal and timing, not broken.</li>
<li><i>"I need to try harder to sleep."</i> → Sleep is the one thing effort makes worse. Your job is to set things up and get out of the way.</li>
<li><i>"I should stay in bed to at least rest."</i> → Lying awake in bed trains wakefulness. Resting in a chair is fine.</li>
<li><i>"Tonight's going to be bad, I can tell."</i> → Predictions about sleep are usually wrong. Notice the thought and let it pass.</li>
</ul>`,
  },
  {
    id: 'paradox',
    title: 'Trying to stay awake (paradoxical intention)',
    mins: 1,
    body: `
<p>Lie in bed in the dark with your eyes open and <b>gently try to stay awake</b>, without phone, screens or activity. Don't fight sleep hard; just give up the job of trying to fall asleep.</p>
<p>Removing the pressure to sleep lowers "sleep effort" and performance anxiety, and trials show it helps people fall asleep faster. It feels strange and it often works.</p>`,
  },
  {
    id: 'one-bad-night',
    title: 'After a bad night',
    mins: 1,
    body: `
<ul>
<li>Get up at your anchor. Don't sleep in.</li>
<li>Get morning light.</li>
<li>No naps. If you absolutely must, keep it under 20 min and before 3 pm, though during the program it's better to skip it.</li>
<li>Caffeine as usual but not after your cutoff. Don't add extra.</li>
<li>Don't go to bed early. The sleep drive you build today is what fixes tonight.</li>
<li>Don't drive when drowsy.</li>
</ul>
<p>One bad night is data, not a disaster.</p>`,
  },
  {
    id: 'experiments',
    title: 'Running your own experiments',
    mins: 1,
    body: `
<p>Tag diary entries (podcast in bed, alcohol, late caffeine, Worry Time done) and the Review screen will compare how long it took you to fall asleep on nights with and without each one. It waits until there are at least 5 nights on each side.</p>
<p>Try: <b>5 nights with no audio in bed vs 5 nights with audio on a 15-min timer</b>. Let your own data decide.</p>`,
  },
  {
    id: 'relapse',
    title: 'Keeping it fixed',
    mins: 2,
    body: `
<p>Bad patches will happen (exams, stress, travel). What matters is not letting them become habits again.</p>
<ul>
<li><b>Never give up the anchor.</b> It's the one rule to keep forever.</li>
<li>If you have 3+ bad nights in a row: restart the diary, apply the bed rules strictly, and run a mini sleep window for a week.</li>
<li>Keep Worry Time as a tool for stressful weeks.</li>
<li>If ISI is still 15 or more after 8 weeks of honest effort, see a GP and ask about a sleep psychologist. THIS WAY UP's free Insomnia Program is also a good next step.</li>
</ul>`,
  },
];

export const SHUFFLE_WORDS = [
  'blanket', 'garden', 'harbour', 'lantern', 'pebble', 'meadow', 'teapot', 'button', 'cradle', 'velvet',
  'orchard', 'feather', 'candle', 'pillow', 'marble', 'saddle', 'willow', 'biscuit', 'compass', 'dolphin',
];

export const SHUFFLE_ITEMS = {
  a: ['apple', 'anchor', 'acorn', 'armchair', 'avocado', 'antelope', 'apron'],
  b: ['balloon', 'bucket', 'bicycle', 'banana', 'bridge', 'bubble', 'basket'],
  c: ['cactus', 'cloud', 'carrot', 'canoe', 'cupcake', 'castle', 'cow'],
  d: ['daisy', 'door', 'drum', 'duck', 'desert', 'donut', 'dice'],
  e: ['egg', 'eagle', 'envelope', 'elbow', 'easel', 'elephant', 'eel'],
  f: ['fern', 'fork', 'fox', 'fountain', 'flag', 'fig', 'fence'],
  g: ['grape', 'goat', 'guitar', 'gate', 'glove', 'goose', 'globe'],
  h: ['hammock', 'hat', 'hill', 'honey', 'harp', 'horse', 'hedge'],
  i: ['igloo', 'ink', 'iron', 'island', 'ivy', 'icicle', 'iguana'],
  j: ['jar', 'jelly', 'jacket', 'jungle', 'jug', 'jigsaw', 'jetty'],
  k: ['kite', 'kettle', 'key', 'koala', 'kayak', 'kiwi', 'knot'],
  l: ['lemon', 'ladder', 'leaf', 'lighthouse', 'lamb', 'lake', 'lily'],
  m: ['moon', 'mitten', 'mango', 'mountain', 'mug', 'moss', 'map'],
  n: ['nest', 'needle', 'napkin', 'nut', 'net', 'noodle', 'newt'],
  o: ['owl', 'oar', 'olive', 'onion', 'oven', 'otter', 'oak'],
  p: ['peach', 'paddle', 'pond', 'pumpkin', 'piano', 'parrot', 'pine'],
  q: ['quilt', 'quail', 'queen', 'quartz', 'quiche', 'quill', 'quokka'],
  r: ['rainbow', 'rabbit', 'rope', 'river', 'radish', 'rocket', 'rug'],
  s: ['snail', 'spoon', 'sail', 'sock', 'shell', 'strawberry', 'swing'],
  t: ['tulip', 'teacup', 'tent', 'turtle', 'train', 'tomato', 'tree'],
  u: ['umbrella', 'ukulele', 'unicorn', 'urn', 'utensil', 'uniform', 'udon'],
  v: ['violin', 'vase', 'van', 'vine', 'valley', 'vest', 'volcano'],
  w: ['wagon', 'whale', 'window', 'walnut', 'wave', 'wheel', 'wool'],
  x: ['xylophone', 'x-ray', 'xenops'],
  y: ['yacht', 'yarn', 'yak', 'yoghurt', 'yo-yo', 'yam', 'yard'],
  z: ['zebra', 'zip', 'zucchini', 'zoo', 'zeppelin', 'zinnia', 'zigzag'],
};

// Progressive muscle relaxation: [group, tense instruction]
export const PMR = [
  ['Hands', 'Make tight fists.'],
  ['Forearms & upper arms', 'Bend your elbows and tense your arms.'],
  ['Shoulders', 'Lift your shoulders up towards your ears.'],
  ['Forehead', 'Raise your eyebrows high.'],
  ['Eyes & cheeks', 'Squeeze your eyes shut.'],
  ['Jaw', 'Clench your teeth gently.'],
  ['Neck', 'Press your head back into the pillow.'],
  ['Chest', 'Take a deep breath and hold it.'],
  ['Stomach', 'Tighten your stomach muscles.'],
  ['Buttocks', 'Squeeze your buttocks together.'],
  ['Thighs', 'Press your knees together and tense your thighs.'],
  ['Calves', 'Point your toes towards your face.'],
  ['Feet', 'Curl your toes down.'],
];

export const GET_UP_IDEAS = [
  'Sit in a dim room and listen to a boring or familiar podcast',
  'Read something mildly dull on paper (a textbook works)',
  'Fold laundry slowly',
  'Do slow breathing or PMR in a chair',
  'Gentle stretching on the floor',
  'Write down whatever is on your mind, then close the book',
];

export const PI_SCRIPT = [
  'Lie back and get comfortable.',
  'Keep your eyes gently open in the dark.',
  'Your only job now is to stay awake a little longer. No phone, no screens.',
  'Don\'t fight sleep hard. Just let go of trying to fall asleep.',
  'If your eyelids feel heavy, that\'s fine. Notice it and keep gently watching the dark.',
  'There\'s nothing to achieve tonight. Just rest your eyes open.',
];
