/*
  pvpConsumption.ash [v1.3]
    a simple "did I consume this before?" script that grew
    into also checking for uneaten food for the "Balance Diet" pvp mini

  todo: handle non-items like hot dog stand, sushi, snootee, etc
 */
script "pvpConsumption.ash";

// -- start customizable variables
// gotta be maintained :(
string pvp_date_filename = 'pvpSeason52_dates.txt';
string fruitcakelist_filename = 'fruitcake_list.txt';

// something seems inconsistent about how kolmafia renders html,
// so if it is formatting it weirdly, you can toggle this
boolean PLAIN_PRINT = false;

// sort direction, either 'asc' or 'desc'
string QUALITY_SORT = 'asc';
string SIZE_SORT = 'asc';

// the int doesn't matter, I just have no idea how to use `contains` otherwise
// feel free to add your own exclusions in the same manner
int[string] EXCLUDED_ITEM_NAMES = {
  "Quantum Taco": 1,
  "Pirate Fork": 1,
  "Schrödinger's thermoses": 1,
};
// -- end customizable variables

string[int] PVP_DATES;
string[int] FRUITCAKE_LIST;

string NUMBERS_REGEX = "((?:\\d{1,3})(?:,\\d{3})*(?:\.\\d+)?)";
string CONSUME_AMOUNT_REGEX = "(?:<td>)((?:\\d{1,3})(?:,\\d{3})*(?:\.\\d+)?)(?:<\/td>)";
string CONSUME_DATE_REGEX = "(?:<small>)(.*?)(?:<\/small>)";

buffer visit_recent_consumption() {
  return visit_url("showconsumption.php?recent=1");
}
string[int] fetchFruitCakes() {
  if (FRUITCAKE_LIST.count() <= 0) {
    boolean isLoaded = file_to_map(fruitcakelist_filename, FRUITCAKE_LIST);
    if (!isLoaded) abort('Unable to load fruitcakes.');
  }

  return FRUITCAKE_LIST;
}
string[int] fetchDates() {
  if (PVP_DATES.count() <= 0) {
    // using a hack to generate list of dates that current season is in
    boolean isLoaded = file_to_map(pvp_date_filename, PVP_DATES);
    if (!isLoaded) abort('Unable to load list of dates for PVP Season 52.');
  }

  return PVP_DATES;
}
int findDateIdx(string date) {
  string[int] dates = fetchDates();

  foreach idx, otherDate in dates {
    if (otherDate == date) {
      return idx;
    }
  }

  return -1;
}
boolean isWithinDays(string date, int limit) {
  int dateIdx = findDateIdx(date);
  if (dateIdx == -1) {
    return false;
  }

  string today = format_date_time('yyyyMMdd', today_to_string(), 'yyyy-MM-dd');
  int todayIdx = findDateIdx(today);
  if (todayIdx == -1) {
    print('It does not seem like today is within PVP Season 52.', 'maroon');
    return false;
  }

  return (todayIdx - dateIdx) < limit;
}
string build_item_regex(string itemName, boolean isForPVP) {
  return '(' + itemName + ')<\/a>(?:.{18}|.{3})<\/td>' + CONSUME_AMOUNT_REGEX + '<td nowrap>' + CONSUME_DATE_REGEX;
}
string build_item_regex(string itemName) {
  return build_item_regex(itemName, false);
}
int get_quality_value(item food) {
  switch (food.quality.to_lower_case()) {
    case 'epic':
      return 5;
    case 'awesome':
      return 4;
    case 'good':
      return 3;
    case 'decent':
      return 2;
    case 'crappy':
      return 1;
    case '???':
      // return 6;
    default:
      return 0;
  }
}
string get_quality_color(item food) {
  switch (food.quality.to_lower_case()) {
    case 'epic':
      return '#8a2be2';
    case 'awesome':
      return 'blue';
    case 'good':
      return 'green';
    case 'decent':
      return '#888044';
    case 'crappy':
      return '#999999';
    case '???':
    default:
      return 'black';
  }
}
string get_sort_value(item food) {
  int qualityValue = get_quality_value(food);
  if (QUALITY_SORT == 'desc') {
    qualityValue = 5 - qualityValue;
  }

  int sizeValue = food.fullness;
  if (SIZE_SORT == 'desc') {
    sizeValue = 100 - sizeValue;
  }

  return qualityValue + '/' + sizeValue + '/' + '-' + food.name.to_lower_case();
}
boolean is_fruitcake(string foodname) {
  fetchFruitCakes();

  foreach idx, fruitcake_name in FRUITCAKE_LIST {
    if (to_lower_case(foodname) == to_lower_case(fruitcake_name)) {
      return true;
    }
  }

  return false;
}
boolean have_consumed(string itemName, boolean isForPVP) {
  buffer consumptionHistory = visit_recent_consumption();
  string rowregex = build_item_regex(itemName, isForPVP);

  matcher match = create_matcher(rowregex, consumptionHistory);
  boolean matchFound = match.find();
  if (!matchFound) {

    return false;
  }

  string consumeAmt = match.group(2);
  string consumeDate = match.group(3).substring(0, 10);

  if (isForPVP && !isWithinDays(consumeDate, 30)) {
    print('Nope, never consumed "' + itemName + '" for pvp season 52.', 'green');
    if (is_fruitcake(itemName)) print(" and it's a fruit/cake!", 'green');

    return false;
  }

  print('Consumed  "' + itemName + '" ' + consumeAmt + ' times where latest was ' + consumeDate, 'green');
  return true;
}
boolean have_consumed(string itemName) {
  return have_consumed(itemName, false);
}
item[int] find_unconsumed_food(int[item] sourceList, boolean isForPVP) {
  item[int] recommendedItems; // returned list

  buffer consumptionHistory = visit_recent_consumption();

  // look for uneaten items
  foreach it in sourceList {
    // use fullness to check if item is food
    if (it.fullness <= 0) continue;

    // skip excluded items
    if (EXCLUDED_ITEM_NAMES contains it.name) continue;

    // check if listed in consumption history
    string rowregex = build_item_regex(it.name, isForPVP);
    matcher match = create_matcher(rowregex, consumptionHistory);
    boolean matchFound = match.find();

    // skip if found
    if (matchFound) {
      if (!isForPVP) continue; // and not for pvp

      // skip if it's within 30 days for pvp
      string consumeDate = match.group(3).substring(0, 10);
      if (isForPVP && isWithinDays(consumeDate, 30)) {
        continue;
      }
    }

    // looks good, so add it to the list of recommendations
    int newIdx = recommendedItems.count();
    recommendedItems[newIdx] = it;
  }

  return recommendedItems;
}
item[int] find_unconsumed_food() {
  int[item] inventory = get_inventory();
  return find_unconsumed_food(inventory, false);
}
item[int] find_owned_fruitcakes() {
  fetchFruitCakes();
  item[int] recommendedItems; // returned list

  foreach idx, fruitcake_name in FRUITCAKE_LIST {
    item fruitcakeItem = to_item(fruitcake_name);
    if (available_amount(fruitcakeItem) <= 0) {
      continue;
    }
    // looks good, so add it to the list of recommendations
    int newIdx = recommendedItems.count();
    recommendedItems[newIdx] = fruitcakeItem;
  }

  return recommendedItems;
}
string create_quality_size_html(item food) {
  string quality = food.quality;
  if (quality == '') {
    quality = '???';
  }

  string color = get_quality_color(food);

  return '<span style="font-size: 9px; color: ' + color + ';">(' + quality + ', size: ' + food.fullness + ')</span>';
}
void print_recommended_list(item[int] recommendedList) {
  sort recommendedList by get_sort_value(value);
  string html = '<table border="1">';

  foreach x, food in recommendedList {
    string lineitem_html = '<tr>';
    lineitem_html += '<td style="display: flex; flex-direction: row; width: 500px;">';
    lineitem_html += '<span>' + food.name + '</span> ';
    lineitem_html += create_quality_size_html(food);

    if (is_fruitcake(food.name)) {
      lineitem_html += ' <span style="font-size: 9px; color: #ca7a88;">(fruit/cake!)</span>';
    }

    lineitem_html += '</td>';
    lineitem_html += '</tr>';
    html += lineitem_html;
  }

  html += '</ul>';
  print_html(html);
}
void print_recommended_list_plain(item[int] recommendedList) {
  sort recommendedList by get_sort_value(value);

  foreach x, food in recommendedList {
    string printstring = '• ' + food.name + ' (' + food.quality + ', ' + food.fullness + ')';
    if (is_fruitcake(food.name)) {
      printstring += ' (fruit/cake!)';
    }
    print(printstring);
  }
}
void print_owned_fruitcakes_list() {
  item[int] fruitcakeList = find_owned_fruitcakes();
  sort fruitcakeList by get_sort_value(value);
  string html = '<table border="1">';

  foreach x, food in fruitcakeList {
    string lineitem_html = '<tr>';
    lineitem_html += '<td style="display: flex; flex-direction: row; width: 500px;">';
    lineitem_html += '<span>' + food.name + '</span> ';
    lineitem_html += create_quality_size_html(food);
    lineitem_html += '</td>';
    lineitem_html += '</tr>';
    html += lineitem_html;
  }

  html += '</table>';
  print_html(html);
}
void abort_help() {
  print('-- Help --', 'red');
  print('Give me "[inventory/inv/storage/stor] (any/pvp) (plain/color)"');
  print('');
  print('example: "pvpconsumption stor" will print out unique foods in hagnk\'s storage that have not been consumed before.');
  print('example: "pvpconsumption inv any plain" will print any unique foods you have not consumed before in plaintext.');
  print('example: "pvpconsumption" by default is equivalent to "pvpconsumption inv pvp color"');
  print('');
  print('Bonus feature: "pvpconsumption fruitcake" to list out items in your inventory that are valid fruit/cakes.');
  print('');
  print('Bug: if the CLI seems to clear out after running use PLAIN_PRINT=true setting. Not sure why it does that.');
  abort();
}
void main(string arguments) {
  if (arguments == 'help') {
    abort_help();
  }

  string[int] argParts = arguments.split_string(' ');
  boolean isForPVP = true;
  string checkSource = 'inventory';

  if (argParts[0] != '') {
    checkSource = argParts[0];
  }

  if (argParts[0] == 'fruitcake') {
    print_owned_fruitcakes_list();
    return;
  }

  // handle custom args
  if (argParts.count() >= 2) {
    if (argParts[1] == 'any') {
      isForPVP = false;
    } else if (argParts[1] == 'pvp') {
      isForPVP = true;
    }

    if (argParts[1] == 'plain') {
      PLAIN_PRINT = true;
    } else if (argParts[1] == 'color') {
      PLAIN_PRINT = false;
    }
  }

  if (argParts.count() >= 3) {
    if (argParts[2] == 'plain') {
      PLAIN_PRINT = true;
    } else if (argParts[2] == 'color') {
      PLAIN_PRINT = false;
    }
  }

  if (checkSource == 'inv') {
    checkSource = 'inventory';
  } else if (checkSource == 'stor') {
    checkSource = 'storage';
  }

  if (checkSource != 'inventory' && checkSource != 'storage') {
    abort_help();
  }

  if (isForPVP) {
    print('Checking ' + checkSource + ' for foods you have not consumed for pvp season 52...', 'olive');
  } else {
    print('Checking ' + checkSource + ' for foods you have not consumed...', 'olive');
  }

  if (QUALITY_SORT != 'asc' && QUALITY_SORT != 'desc') {
    print('Warning: your QUALITY_SORT does nothing.', 'orange');
  }
  if (SIZE_SORT != 'asc' && SIZE_SORT != 'desc') {
    print('Warning: your SIZE_SORT does nothing.', 'orange');
  }

  // where to check
  int[item] sourceList;
  if (checkSource == 'inventory') {
    sourceList = get_inventory();
  } else if (checkSource == 'storage') {
    sourceList = get_storage();
  }

  if (sourceList.count() <= 0) {
    abort('Your ' + checkSource + ' is empty.');
  }

  // display style
  if (!PLAIN_PRINT) {
    print_recommended_list(find_unconsumed_food(sourceList, isForPVP));
  } else {
    print_recommended_list_plain(find_unconsumed_food(sourceList, isForPVP));
  }
}
