drop table tr_t;
CREATE TABLE TR_T 
(A NUMBER(3),
B NUMBER(3),
C NUMBER(6,2));
delete from tr_t;
INSERT INTO TR_T VALUES (2,1,8);
INSERT INTO TR_T VALUES (2,2,2);
INSERT INTO TR_T VALUES (2,3,4);
INSERT INTO TR_T VALUES (2,4,7);
INSERT INTO TR_T VALUES (1,4,6);
INSERT INTO TR_T VALUES (1,3,5);
INSERT INTO TR_T VALUES (1,2,3);
INSERT INTO TR_T VALUES (1,1,4);
/
SET serveroutput ON 
CREATE OR REPLACE PACKAGE my_math IS 
PROCEDURE transp_theor(sell_str VARCHAR2,cust_str VARCHAR2); 
END my_math; 
/ 
CREATE OR REPLACE PACKAGE BODY my_math IS 
neg_val exception;
not_int exception;
m tr_t.A%TYPE:=0; 
n tr_t.b%TYPE:=0;
--переменные для фиктивных поставщиков и потребителей
fict_s tr_t.A%TYPE;
fict_c tr_t.b%TYPE;
TYPE as_t IS TABLE OF tr_t.c%TYPE INDEX BY pls_integer; 
TYPE mtrx IS TABLE OF as_t INDEX BY pls_integer;--матрица 
transp_tab mtrx; 
c mtrx;--матрица стоимостей
PROCEDURE fill(str VARCHAR2,tab out nocopy as_t,num out nocopy NUMBER);
PROCEDURE checking(supply NUMBER,DEMAND NUMBER);
PROCEDURE meth_pot(op_t IN out nocopy mtrx);
PROCEDURE meth_north_w;
PROCEDURE get_one(equa IN out nocopy mtrx);
PROCEDURE re_calc(op_t IN out nocopy mtrx,check_m mtrx);
PROCEDURE FINISH(op_t IN out nocopy mtrx);
--"Main"
PROCEDURE transp_theor(sell_str VARCHAR2,cust_str VARCHAR2) IS
CURSOR tr_cur IS 
SELECT * FROM tr_t ORDER BY A,b; 
TYPE tab_rec IS TABLE OF tr_cur%rowtype INDEX BY pls_integer;
ur_t tab_rec; 
A as_t; 
b as_t; 
inv_cnt_s exception; 
inv_cnt_c exception; 
inv_inp_s exception; 
inv_inp_c exception; 
null_indx exception;
pragma exception_init (null_indx,-06502);
num NUMBER;
num_s NUMBER:=0;
num_c NUMBER:=0;
--сравнение содержимого исходной таблицы и параметров (соответствие)
PROCEDURE compare(u tab_rec, t as_t, num IN out nocopy NUMBER, ty NUMBER) IS
flag boolean:=FALSE;
tmp tr_t.A%TYPE;
BEGIN
num:=t.FIRST;
loop
FOR i IN 1..u.count loop
CASE ty
WHEN 1 THEN tmp:=u(i).A;
WHEN 2 THEN tmp:=u(i).b;
END CASE;
flag:=(tmp=num);
IF flag THEN 
exit; 
END IF;
END loop;
IF NOT flag THEN
IF ty=1 THEN
raise inv_inp_s;
ELSE 
raise inv_inp_c;
END IF;
END IF;
num:=t.NEXT(num);
IF num IS NULL THEN exit; END IF;
END loop;
END compare;

BEGIN 
--получаем количество потреб. и поставщиков. 
SELECT count(DISTINCT A) INTO m FROM tr_t; 
SELECT count(DISTINCT b) INTO n FROM tr_t; 
--заполняем таблицы для хранения информации о потребностях и наличии 
fill(sell_str,A,num);
fill(cust_str,b,num);
--сравниваем по количеству
IF A.count!=m 
THEN raise inv_cnt_s;
END IF;
IF b.count!=n
THEN raise inv_cnt_c;
END IF;
num:=1;
--Заполняем значениями из исходной таблицы временную таблицу
FOR rec IN tr_cur loop
--Проверка значений в исходной таблице.
IF rec.A<=0 OR rec.b<=0
OR rec.c<0 
THEN raise neg_val;
elsif (rec.A)<>(floor(rec.A)) OR (rec.b)<>(floor(rec.b)) 
THEN raise not_int;
END IF;
ur_t(num):=rec;
num:=num+1;
END loop;
compare(ur_t,A,num,1);
compare(ur_t,b,num,2);
--Составляем матрицу, задающую транспортную задачу. Занести поставщиков, затем потребителей, стоимость и ресурсы.
--заносим номера поставщиков
num:=A.FIRST;
FOR i IN 1..m loop
transp_tab(i+1)(1):=num;
transp_tab(i+1)(n+2):=A(num);
num:=A.NEXT(num);
IF num IS NULL THEN exit; 
END IF;
END loop;
--заносим потребителей
num:=b.FIRST;
FOR i IN 1..n loop
transp_tab(1)(i+1):=num;
transp_tab(m+2)(i+1):=b(num);
num:=b.NEXT(num);
IF num IS NULL THEN exit; 
END IF;
END loop;
--заносим информацию о стоимости перевозок. 
num:=1;
FOR i IN 2..m+1 loop
FOR j IN 2..n+1 loop
transp_tab(i)(j):=ur_t(num).c;
num:=num+1;
END loop;
END loop;
num:=A.FIRST;
FOR i IN 1..m loop
--получение общего количества запасов поставщиков
num_s:=num_s+A(num);
num:=A.NEXT(num);
IF num IS NULL THEN exit; 
END IF;
END loop;
num:=b.FIRST;
FOR i IN 1..n loop
--получение общего количества потребностей покупателей
num_c:=num_c+b(num);
num:=b.NEXT(num);
IF num IS NULL THEN exit; 
END IF;
END loop;
--Проверка на равенство предложения спросу.
checking(num_s,num_c);
exception 
WHEN inv_cnt_s THEN dbms_output.put_line('Введено неверное число поставщиков.'); 
WHEN inv_cnt_c THEN dbms_output.put_line('Введено неверное число потребителей.'); 
WHEN inv_inp_s THEN dbms_output.put_line('Не найдено соответствия для номера поставщика: '||num||' в исходной таблице.'); 
WHEN inv_inp_c THEN dbms_output.put_line('Не найдено соответствия для номера потребителя: '||num||' в исходной таблице.');
WHEN null_indx THEN dbms_output.put_line('Хотя бы один параметр введен неверно или пуст.');
WHEN neg_val THEN dbms_output.put_line('Проверьте вводимые данные и значения в исходной таблице. Номер поставщика,потребителя, количественные значения должны быть >0, стомость =>0');
WHEN not_int THEN dbms_output.put_line('Проверьте вводимые данные и значения в исходной таблице. Номер поставщика,потребителя и количественные значения должны быть целыми.');
--удалить!!!
WHEN no_data_found THEN dbms_output.put_line('Что-то пошло не так! данных нема!');
END transp_theor; 
--процедура заполнения таблиц
PROCEDURE fill(str VARCHAR2,tab out nocopy as_t,num out NUMBER) IS
i tr_t.A%TYPE:=1;
tmp NUMBER;
BEGIN
loop
num:=to_number(REPLACE(regexp_substr(str,'\S+',1,i+1),'.',','));
IF num IS NULL THEN exit;
END IF;
tmp:=to_number(REPLACE(regexp_substr(str,'\S+',1,i),'.',','));
IF num<=0 OR tmp<=0
THEN raise neg_val;
elsif (num)<>(floor(num)) OR (tmp)<>(floor(tmp)) 
THEN raise not_int;
END IF;
tab(tmp):=num;
i:=i+2;
END loop;
END fill;
PROCEDURE checking(supply NUMBER,DEMAND NUMBER) IS
--добавление фиктивного поставщика
PROCEDURE add_sell IS
num tr_t.A%TYPE:=-1;--несуществующий номер
BEGIN
--сдвигаем содержимое матрицы на строчку ниже (строку потребностей) и добавление стоимости=0;
FOR j IN 2..n+1 loop
transp_tab(m+3)(j):=transp_tab(m+2)(j);
transp_tab(m+2)(j):=0;
END loop;
--добавление номера продавца и его "запасов".
FOR i IN 2..m+1 loop
IF num<transp_tab(i)(1)
THEN num:=transp_tab(i)(1);
END IF;
END loop;
transp_tab(m+2)(n+2):=DEMAND-supply;
transp_tab(m+2)(1):=num+1;
fict_s:=num+1;
m:=m+1;--стало на одного поставщика больше
END add_sell;
--добавление фиктивного потребителя
PROCEDURE add_cust IS
num tr_t.A%TYPE:=-1;--несуществующий номер
BEGIN
FOR i IN 2..m+1 loop
transp_tab(i)(n+3):=transp_tab(i)(n+2);
transp_tab(i)(n+2):=0;
END loop;
--добавление номера потребителя и его "потребностей".
FOR j IN 2..n+1 loop
IF num<transp_tab(1)(j)
THEN num:=transp_tab(1)(j);
END IF;
END loop;
transp_tab(m+2)(n+2):=supply-DEMAND;
transp_tab(1)(n+2):=num+1;
fict_c:=num+1;
n:=n+1;--стало на одного потребителя больше
END add_cust;
BEGIN
IF supply<DEMAND 
THEN add_sell;
elsif
supply>DEMAND 
THEN add_cust;
END IF;
--метод северо-западного угла
meth_north_w;
END checking;

PROCEDURE meth_north_w IS
num tr_t.A%TYPE:=2;--индекс по строкам первого поставщика(в любом случае)
cnt_c num%TYPE;
cnt_s num%TYPE;
k num%TYPE:=1;
op_t mtrx;
BEGIN
cnt_s:=transp_tab(num)(n+2);--запас 
FOR i IN 2..n+1 loop
cnt_c:=transp_tab(m+2)(i);--потребность i-го потребителя
while(cnt_c<>0) loop
IF (cnt_c<=cnt_s)--потребностти удовлетворены
THEN op_t(k)(i-1):=cnt_c;
     cnt_s:=cnt_s-cnt_c;
     cnt_c:=0;
ELSE op_t(k)(i-1):=cnt_s;--не хватает запасов, записываем, что есть
     cnt_c:=cnt_c-cnt_s;
     cnt_s:=0;
END IF;
IF (cnt_s=0 AND num<m+1)--поставщик исчерпан
THEN num:=num+1;--выбираем след поставщика
cnt_s:=transp_tab(num)(n+2);
--доп условие-избежание вырожденности опорного плана
IF cnt_c=0
THEN op_t(k)(i):=0;
END IF;
k:=k+1;--запись теперь будет ниже в опорной таблице
END IF;
END loop;
END loop;
--заполняем C
FOR i IN 2..m+1 loop
FOR j IN 2..n+1 loop
c(i-1)(j-1):=transp_tab(i)(j);
END loop;
END loop;
meth_pot(op_t);
END meth_north_w;

PROCEDURE meth_pot(op_t IN out nocopy mtrx) IS
c_op_t mtrx;
check_m mtrx;
equa mtrx;
cnt NUMBER(4):=0;
flag boolean:=FALSE;

FUNCTION look_eq(p NUMBER) RETURN NUMBER IS
BEGIN
FOR z IN 1..m+n-1 loop
IF equa(z)(p)=1
THEN RETURN equa(z)(m+n+1);--значение потенциала
END IF;
END loop;
RETURN 0;--для v-последнего
END look_eq;
BEGIN
--заполняем C_Op_t в соответствии с опорным планом и матрицей стоимостей.
FOR i IN 1..m loop
FOR j IN 1..n loop
IF op_t(i).EXISTS(j) THEN
c_op_t(i)(j):=c(i)(j);
END IF;
END loop;
END loop;
--заполняем матрицу уравнений
FOR i IN 1..m+n-1 loop
FOR j IN 1..m+n+1 loop
equa(i)(j):=0;
END loop;
END loop;
cnt:=1;
FOR i IN 1..m loop
FOR j IN 1..n loop
IF c_op_t(i).EXISTS(j) THEN
equa(cnt)(i):=1;
equa(cnt)(j+m):=1;
equa(cnt)(m+n+1):=c_op_t(i)(j);
cnt:=cnt+1;
END IF;
END loop;
END loop;
--зануляем последний потенциал-все вхождения в уравнения.
FOR i IN 1..m+n-1 loop
equa(i)(m+n):=0;
END loop;
--посчитаем уравнения
get_one(equa);
--заполняем оставшиеся пустые ячейки c_opt_t
FOR i IN 1..m loop
  FOR j IN 1..n loop
  IF NOT c_op_t(i).EXISTS(j)
  THEN c_op_t(i)(j):=look_eq(i)+look_eq(j+m);--u+v
  END IF;
  END loop;
END loop;
--проверяем решение на оптимальность-оценочная матрица
FOR i IN 1..m loop
  FOR j IN 1..n loop
  check_m(i)(j):=c(i)(j)-c_op_t(i)(j);
  IF check_m(i)(j)<0 THEN flag:=TRUE;
  END IF;
  END loop;
END loop;
--проверка на оптимальность-значения матрицы
IF flag
THEN re_calc(op_t,check_m);
ELSE
FINISH(op_t);
END IF;
END meth_pot;

PROCEDURE get_one(equa IN out nocopy mtrx) IS
tmp NUMBER(4):=0;
cons NUMBER(4):=0;
cnt NUMBER(4):=0;
flag boolean:=TRUE;
b as_t;
BEGIN
--поиск строки с единственной единицей
while flag loop
flag:=FALSE;
<<i_t>>
FOR i IN 1..m+n-1  loop--смотрим с конца
  cnt:=0;
  FOR j IN 1..m+n loop--ищем первую единицу в строке. на каждом i в строке будет лишь одна единица
  IF equa(i)(j)=1 
  THEN cnt:=cnt+1;
  tmp:=j;
  END IF;
  IF cnt>1 THEN CONTINUE i_t;
  END IF;
  END loop;
  IF cnt=1 AND NOT b.EXISTS(i)--еще эту строчку не рассматривали
  THEN cons:=tmp; 
  tmp:=i;
  b(tmp):=1;
  flag:=TRUE; 
  exit; END IF;
END loop;
--отнятие 
FOR i IN 1..m+n-1 loop
  IF NOT b.EXISTS(i) AND equa(i)(cons)=1--на той же позиции единица
  THEN equa(i)(cons):=0;--отняли единицу
       equa(i)(m+n+1):=equa(i)(m+n+1)-equa(tmp)(m+n+1);
  END IF;
  END loop;
END loop;
END get_one;

PROCEDURE re_calc(op_t IN out nocopy mtrx,check_m mtrx) IS
TYPE as_t_str IS TABLE OF VARCHAR2(1) INDEX BY pls_integer; 
TYPE mtrx_str IS TABLE OF as_t_str INDEX BY pls_integer;--матрица 
bool mtrx; 
x NUMBER(4):=0;
y NUMBER(4):=0;
tmp NUMBER(4):=0;
i_t NUMBER(4);
j_t NUMBER(4);
alt_sig mtrx_str;--расстановка + и -, для перерасчета
TYPE r_z IS record 
(i NUMBER(4), j NUMBER(4));
TYPE t_z IS TABLE OF r_z INDEX BY pls_integer;
zero_m t_z;
cnt_tmp NUMBER(4):=0;
tmp_tab t_z;--хранение шагов
cnt NUMBER(4):=1;
tmp_i NUMBER(4);
tmp_j NUMBER(4);
PROCEDURE init_c IS
flag boolean:=FALSE;
cnt_str NUMBER(4):=0;
cnt_st NUMBER(4):=0;
tmp_dist NUMBER(4):=m;
tmp_dist_i NUMBER(4):=1;
i_f_c NUMBER(4):=1;
  PROCEDURE clean IS
  BEGIN
  bool(i_t).DELETE(j_t);----удаляем из базиса, чтобы снова не попасть 
  alt_sig(i_t).DELETE(j_t);--удаляем из базиса, чтобы снова не попасть 
  --если клетка не откатная, откатываемся на последнее значение в таблице шагов, если откатная, удаляем текущее и на пред. 
  IF i_t=tmp_tab(cnt_tmp).i AND j_t=tmp_tab(cnt_tmp).j 
  THEN
   --сначала удаляем шаг, на которой эта клетка. затем откатываем на пред
  tmp_tab.DELETE(cnt_tmp);
  cnt_tmp:=cnt_tmp-1;--новый номер последнего элемента
  i_t:=tmp_tab(cnt_tmp).i;
  j_t:=tmp_tab(cnt_tmp).j;
  ELSE
  i_t:=tmp_tab(cnt_tmp).i;
  j_t:=tmp_tab(cnt_tmp).j;
  END IF;
  init_c;

  END clean;
  
  FUNCTION con_t RETURN boolean IS
  BEGIN
  cnt_st:=0;
  FOR i IN 1..m loop
  IF alt_sig.EXISTS(i) AND  alt_sig(i).EXISTS(j_t) 
  THEN cnt_st:=cnt_st+1;
  END IF;
  END loop;
   cnt_str:=0;
  FOR j IN 1..n loop
  IF  alt_sig.EXISTS(i_t) AND  alt_sig(i_t).EXISTS(j)
  THEN cnt_str:=cnt_str+1;
  END IF;
  END loop;
RETURN (cnt_st>2 OR cnt_str>2);
END con_t;

BEGIN
IF i_t=x AND j_t=y 
THEN loop
     IF i_f_c<>x AND (bool.EXISTS(i_f_c) AND bool(i_f_c).EXISTS(j_t)) AND tmp_dist>abs(i_f_c-x)
     THEN 
     tmp_dist:=abs(i_f_c-x);
     tmp_dist_i:=i_f_c;
     END IF;
     i_f_c:=i_f_c+1;
     exit WHEN i_f_c=m+1;
     END loop;
END IF;

<<i_c>>
FOR i IN tmp_dist_i..m loop
IF (i<>i_t) AND (bool.EXISTS(i) AND bool(i).EXISTS(j_t)AND bool(i)(j_t)<>2 ) --есть в базисной клетке
THEN 
      alt_sig(i)(j_t):='-';
      IF con_t
      THEN alt_sig(i).DELETE(j_t);
      CONTINUE;
      ELSE
      IF i=x THEN RETURN; END IF;
      cnt_tmp:=cnt_tmp+1;
      tmp_tab(cnt_tmp).i:=i_t;
      tmp_tab(cnt_tmp).j:=j_t;
      i_t:=i;
     bool(i_t)(j_t):=2;--2 означает, что уже посетили базис
     flag:=TRUE;
     exit i_c;
     END IF;
END IF;
END loop i_c;

<<j_c>>
FOR j IN 1..n loop
IF (j<>j_t) AND ((bool.EXISTS(i_t) AND bool(i_t).EXISTS(j)AND bool(i_t)(j)<>2 )OR (i_t=x AND j=y))--есть в базисной клетке или это начальная клетка
THEN  IF i_t=x AND j=y THEN RETURN;--цикл замкнулся--условие выхода 
ELSE  alt_sig(i_t)(j):='+';
      IF con_t
      THEN alt_sig(i_t).DELETE(j);
      CONTINUE j_c;
      ELSE
      cnt_tmp:=cnt_tmp+1;
      tmp_tab(cnt_tmp).i:=i_t;
      tmp_tab(cnt_tmp).j:=j_t;
      j_t:=j;
     bool(i_t)(j_t):=2;--2 означает, что уже посетили базис
     flag:=TRUE;
     exit j_c;
     END IF;
END IF;
END IF;
END loop;
--проверить, вставили ли что-нибудь или тупик
IF NOT flag THEN clean;
ELSE 
flag:=FALSE;
init_c;
END IF;

END init_c;
BEGIN
--поиск самого отрицательного и заполнение логической таблицы
FOR i IN 1..m loop
FOR j IN 1..n loop
IF NOT (op_t.EXISTS(i) AND op_t(i).EXISTS(j)) 
THEN IF check_m(i)(j)<tmp
     THEN tmp:=check_m(i)(j);
     x:=i;
     y:=j;
     END IF;
END IF;
END loop;
END loop;
--заполнение bool
FOR i IN 1..m loop
FOR j IN 1..n loop
IF  op_t.EXISTS(i) AND op_t(i).EXISTS(j) 
THEN bool(i)(j):=1;
END IF;
END loop;
END loop;

--запись в знаковую матрицу, в яч. с индексом, где находится самый отриц эл в check_m
alt_sig(x)(y):='+';
--расстановка знаков
i_t:=x;
j_t:=y;
init_c;
--Находим минимум среди минусов и меняем опорный план
tmp:=-1;
FOR j IN 2..n+1 loop
IF transp_tab(m+2)(j)>tmp THEN
tmp:=transp_tab(m+2)(j);--искусственный максимум. ищем среди запасов, в опорном плане не мб. быть значения больше
END IF;
END loop;
FOR i IN 1..m loop
  FOR j IN 1..n loop
  IF alt_sig.EXISTS(i) AND alt_sig(i).EXISTS(j) AND alt_sig(i)(j)='-' AND op_t(i)(j)<tmp
  THEN tmp:=op_t(i)(j);
  END IF;
  END loop;
END loop;
--изменяем опорный план
FOR i IN 1..m loop
  FOR j IN 1..n loop
  IF i=x AND j=y 
  THEN op_t(x)(y):=tmp;--прибавили в самый первый плюс
  CONTINUE;
  END IF;
  IF alt_sig.EXISTS(i) AND alt_sig(i).EXISTS(j)
  THEN CASE alt_sig(i)(j)
       WHEN '+' THEN op_t(i)(j):=op_t(i)(j)+tmp;
       WHEN '-' THEN op_t(i)(j):=op_t(i)(j)-tmp;
       END CASE;
  IF op_t(i)(j)=0 THEN zero_m(cnt).i:=i; zero_m(cnt).j:=j; cnt:=cnt+1;
  END IF;
  END IF;
  END loop;
END loop;

IF zero_m.count>1 THEN
--удаляем только один ноль из опорного плана
op_t(zero_m(zero_m.count).i).DELETE(zero_m(zero_m.count).j);
ELSE
tmp_i:=zero_m(1).i;
tmp_j:=zero_m(1).j;
op_t(tmp_i).DELETE(tmp_j);
END IF;

--вызов снова метода потенциалов
meth_pot(op_t);
END re_calc;
PROCEDURE FINISH(op_t IN out nocopy mtrx) IS
s NUMBER(10):=0;
A NUMBER(10);
b NUMBER(10);
d NUMBER(10):=0;
v_op_t VARCHAR2(20);
BEGIN
--определение длины номеров
A:=LENGTH(transp_tab(m+1)(1))+3;
b:=LENGTH(transp_tab(1)(n+1))+3;
FOR i IN 1..m loop
FOR j IN 1..n loop
IF op_t.EXISTS(i) AND op_t(i).EXISTS(j) AND LENGTH(op_t(i)(j))>d-3
THEN d:=LENGTH(op_t(i)(j))+3;
END IF;
END loop;
END loop;
--подсчет затрат
dbms_output.put_line(lpad('A',A,' ')||lpad('B',b,' ')||lpad('D',d,' ')||chr(10)
||lpad('-',A,'-')||' '||lpad('-',b-1,'-')||' '||lpad('-',d-1,'-'));
FOR i IN 1..m loop
FOR j IN 1..n loop
IF op_t.EXISTS(i) AND op_t(i).EXISTS(j) AND op_t(i)(j)<>0
THEN --DBMS_OUTPUT.PUT_LINE('C(i)(j)='||C(i)(j));
     --DBMS_OUTPUT.PUT_LINE('op_t(i)(j)='||op_t(i)(j));
     IF fict_s=transp_tab(i+1)(1) THEN v_op_t:='-'||op_t(i)(j); elsif fict_c=transp_tab(1)(j+1) THEN v_op_t:='+'||op_t(i)(j); ELSE v_op_t:=op_t(i)(j); END IF;
     dbms_output.put_line(lpad(transp_tab(i+1)(1),A,' ')||lpad(transp_tab(1)(j+1),b,' ')||lpad(v_op_t,d,' '));--если поставщик фиктивный, ставим минусы в количестве(сколько не получит магазин)
s:=s+c(i)(j)*op_t(i)(j);
END IF;
END loop;
END loop;
dbms_output.put_line(chr(10)||'Итого: '||s);
END FINISH;
END my_math; 
/
