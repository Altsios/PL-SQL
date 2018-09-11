--undefine str
--define str='1 0 2 10 1' 
SET verify OFF
SET serveroutput ON
PRO Введите целые числа или дробные в формате: 99.99 или 99,99 
--ЧАСТЬ #1
DECLARE
--типы коллекций
TYPE nestt IS TABLE OF NUMBER;
TYPE bool IS TABLE OF NUMBER(1);
TYPE assnest IS TABLE OF nestt INDEX BY pls_integer;--ассоц. массив вложенных таблиц
--коллекции
mas assnest;
str nestt:=nestt();
b bool:=bool();
--переменные
i NUMBER:=1;
indx NUMBER:=2;
num NUMBER;
sum_n NUMBER:=0;
ind_b NUMBER;
sum_str VARCHAR2(1000);
e_invalid_cnt exception;
num_val_err exception;
pragma exception_init (num_val_err,-06502);
--ЧАСТЬ #2
BEGIN
--записываем числа в коллекцию из строки
loop
num:=to_number(REPLACE(regexp_substr('&STR','\S+',1,i),'.',','));
IF num IS NOT NULL 
THEN str.EXTEND ;
     str(i):=num;
     i:=i+1;
ELSE exit;
END IF;
END loop;

--кол-о чисел в строке должно быть не менее 2
num:=str.count;
IF num<2 THEN raise e_invalid_cnt;
END IF;
ind_b:=num;
--ЧАСТЬ #3
--СОРТИРОВКА
FOR z IN 1..num-1 loop
FOR j IN z+1..num loop
IF str(z)>str(j)
THEN i:=str(z);
     str(z):=str(j);
     str(j):=i;
END IF;
END loop;
END loop;
--ЧАСТЬ #4
--сразу записываем слагаемое из N эл-в=кол-у цифр в строке
mas(1):=str;
str.DELETE;
i:=1;
b.EXTEND(num);
--зануление множества
FOR j IN 1..num loop
b(j):=0;
END loop;
--проецируем бинарные множества на элементы отсортированной строки(без 000 и 111)
FOR c IN 2..POWER(2,num)-1 loop --c-номер набора
IF b(num)=1 THEN num:=num-1; 
END IF;
i:=1;
while(b(i)=1) loop
b(i):=0;
i:=i+1;
END loop;
b(i):=1;
--здесь имеем двочиный num-мерный код
FOR z IN 1..ind_b loop
sum_n:=sum_n + b(z);--складываем все элементы множества
END loop;
--не берем пары, где лишь 1 единица
IF sum_n=1--значит элементов ненулевых 1
THEN
sum_n:=0;
CONTINUE;
END IF;
str.EXTEND(sum_n);
sum_n:=1;
FOR z IN 1..ind_b loop
IF b(z)=1 THEN
str(sum_n):=mas(1)(z);
sum_n:=sum_n+1;
END IF;
END loop;
mas(indx):=str;
indx:=indx+1;
str.DELETE;
sum_n:=0;
END loop;
--ЧАСТЬ #5
--убираем повторы
indx:=mas.count;
i:=1;
while(i<>indx) loop--пары смотрим до предпоследнего элемента-удаляем дубли, получаемые перестановкой
 FOR k IN mas.NEXT(i)..indx loop
IF mas.EXISTS(k) AND mas(i)=mas(k)
 THEN mas.DELETE(k);
END IF; 
END loop;
i:=mas.NEXT(i);
END loop;
--ЧАСТЬ #6
i:=1;
--выводим суммы
while(i IS NOT NULL) loop
 FOR z IN 1..mas(i).count loop
 sum_str:=sum_str||'+'||mas(i)(z);
 sum_n:=sum_n+mas(i)(z);
 END loop;
 dbms_output.put_line(ltrim(sum_str,'+')||'='||sum_n);
 sum_n:=0;
 sum_str:='';
i:=mas.NEXT(i);
END loop;
--ЧАСТЬ #7
exception
WHEN e_invalid_cnt THEN dbms_output.put_line('Введенно "" или единственное значение(недостаточно для суммы).');
WHEN num_val_err 
THEN dbms_output.put_line('Введенно (или отсутствует вовсе) неверное выражение.');
END;
/
