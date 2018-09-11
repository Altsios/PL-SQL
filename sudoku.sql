create or replace PACKAGE Sudoku IS
procedure Solve_Me(dir varchar2,file_name varchar2);
END Sudoku;
/
create or replace PACKAGE BODY Sudoku IS
TYPE var_t IS table OF Number(1) index by simple_integer;
TYPE mtrx IS table of var_t index by simple_integer;
My_sud mtrx;
ft  utl_file.file_type;

procedure wr_file(dir varchar2,file_name varchar2,str varchar2) is
begin
ft:=utl_file.fopen(dir,file_name,'A');
utl_file.put_line(ft,chr(10));
utl_file.put_line(ft,str);
utl_file.fCLOSE(ft);
end wr_file;

--Проверяем правильность исходной таблицы и вставку цифры в данную ячейку.
function Check_num(x number,y  Number, num number) return boolean is
--используются при проверке в блоке 3*3 как смещение i и j (x и y)
Add_X number(1):=3*floor((x-1)/3);
Add_Y number(1):=3*floor((y-1)/3);

begin
for i in 1..9 loop
--проверка: в столбце нет этой цифры
if (i<>x) and My_sud(i)(y)=num
then return false;
end if;
--проверка: в строке нет этой цифры
if (i<>y) and My_sud(x)(i)=num
then return false;
end if;
end loop;
--проверка что в блоке нет этой цифры
for i in 1..3 loop
for j in 1..3 loop
if ((Add_X+i<>x) and (Add_Y<>y)) and My_sud(Add_X+i)(Add_Y+j)= num
then return false;
end if;
end loop;
end loop;
return true;
end Check_num;

--нахождение ответа
function Rec(x number,y number) return boolean is
begin
--Обошли все строки. Успешный выход.
if x>9 then return true; end if;
--если клетка изначально заполнена, пропускаем ее, защищая от зачищения в случае отката 
if My_sud(x)(y)<>0 
then return Rec(floor((y)/9)+x,(y mod 9)+1);
end if;

for i in reverse 1..9 loop--вставляем reverse, чтобы получить результат как в примере.
--идем вглубину. Если возвращается false-откат и изменение значения My_sud(x)(y) на 0. Попытки подставить другие значения.
if Check_num(x,y,i)
then My_sud(x)(y):=i;
if Rec(floor((y)/9)+x,(y mod 9)+1) 
then return true;
else
My_sud(x)(y):=0;
end if;
end if;
end loop;
return false;
end Rec;

--Заполнение таблицы цифрами из файла
procedure Solve_Me(dir varchar2,file_name varchar2) IS
Inv_tab EXCEPTION;
No_Sol EXCEPTION;
buffer varchar2(18);
SMALL_BUFF EXCEPTION;
pragma exception_init (SMALL_BUFF,-06502);
Begin
ft:=utl_file.fopen(dir,file_name,'R');
FOR I IN 1..9 LOOP
utl_file.get_line(ft,buffer);
buffer:=regexp_replace(buffer,'[^[:digit:][:space:]]','###############');--вызовем исскуственно переполнение, если обнаружены дробные числа или буквы
FOR J IN 1..9 LOOP
My_sud(I)(J):=REGEXP_SUBSTR(buffer,'\d',1,j);
If My_sud(I)(J) is null then raise SMALL_BUFF;
end if;
END LOOP;
If REGEXP_SUBSTR(buffer,'\d',1,10) is not null then raise SMALL_BUFF;--в строке больше 9 чисел или записали как минимум двузначное 
end if;
END LOOP;
utl_file.fCLOSE(ft);
--Проверка, правильно ли введена исходная задача
for i in 1..9 loop
for j in 1..9 loop
if My_sud(i)(j)<>0 and not Check_num(i,j,My_sud(i)(j))
then RAISE Inv_tab;
end if;
end loop;
end loop;
--Если задача поставлена верно, переходим к рекурсвиному поиску верных цифер.
if Rec(1,1)--если задача имеет решение, то записываем его в файл и выводим на экран.
then
ft:=utl_file.fopen(dir,file_name,'A');
utl_file.put_line(ft,chr(10));
for i in 1..9 loop
buffer:='';
for j in 1..9 loop
dbms_output.put(My_sud(i)(j)||' ');
buffer:=buffer||My_sud(i)(j)||' ';
end loop;
utl_file.put_line(ft,buffer);
dbms_output.put_line(' ');
end loop;
else raise No_Sol;
end if;
utl_file.fCLOSE(ft);
EXCEPTION
WHEN Inv_tab 
THEN dbms_output.put_line('В исходной таблице обнаружены дубли чисел!');
wr_file(dir,file_name,'В исходной таблице обнаружены дубли чисел!');
WHEN No_Sol
THEN dbms_output.put_line('Поставленная задача не имеет решений!');
wr_file(dir,file_name,'Поставленная задача не имеет решений!');
WHEN SMALL_BUFF 
THEN DBMS_OUTPUT.PUT_LINE('Строка исходной таблицы записана неверно/неверный тип файла.'); 
wr_file(dir,file_name,'Строка исходной таблицы записана неверно.');
WHEN UTL_FILE.INVALID_OPERATION
THEN DBMS_OUTPUT.PUT_LINE('Файл отсутствует или он только для чтения.'); 
WHEN UTL_FILE.INVALID_PATH
THEN DBMS_OUTPUT.PUT_LINE('Неверная директория.'); 
End Solve_Me;
END Sudoku;
/
SET SERVEROUTPUT ON
exec SUDOKU.Solve_Me('STUD_PLSQL','Sud1.txt');
/
