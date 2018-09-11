--КОД ПАКЕТА
CREATE OR REPLACE PACKAGE TR_PAK authid current_user IS 
TYPE STR IS TABLE OF BOOLEAN INDEX BY VARCHAR2(30);
--ТАБЛИЦА ДЛЯ ПРЕДОТВРАЩЕНИЯ ЗАЦИКЛИВАНИЯ
CALL_TAB STR;
--ЕСЛИ НА ВХОДЕ ФЛАГ FALSE-ЗАШЛИ ОТ ДОЧЕРНЕЙ ТАБЛИЦЫ, ЕСЛИ НЕТ, ТО ОТ РОДИТЕЛЬСКОЙ
PROCEDURE CR_CAS_TR (FK_TABLE VARCHAR2, FLAG BOOLEAN:=FALSE);
END TR_PAK;
/
CREATE OR REPLACE PACKAGE BODY TR_PAK IS
PROCEDURE CR_CAS_TR (FK_TABLE VARCHAR2, FLAG BOOLEAN:=FALSE)
is --везде, где указано "pk" имеется в виду также unique
    REQ VARCHAR2(32767);
    CASC_CNT number(4) := 0;
    TRG_TAB VARCHAR2(30);
    TYPE PAR_TYPE IS TABLE OF TRG_TAB%TYPE INDEX BY PLS_INTEGER;
    PAR_TAB PAR_TYPE;
    --ссылка на любые реальные курсоры
    TYPE REF_CUR IS REF CURSOR;
    REF_CURSOR_TEXT REF_CUR;
    --тип, описывающий вспомогательную таблицу: имя зависимой таблицы, ограничение fk, колонки fk через запятую, колонки pk через запятую
    TYPE COL_REF_REC IS RECORD (TRG_TAB VARCHAR2(128), CON_ALTER VARCHAR2(128), COLUMS_LISTAGG_FOREIGN VARCHAR2(4000), COLUMS_LISTAGG_REFERENCES VARCHAR2(4000));
    TYPE COL_REF_type IS TABLE OF COL_REF_REC INDEX BY PLS_INTEGER;
    COLUMNS_REFERENCES COL_REF_type;
    
    TYPE TEMP_VARCHAR IS TABLE OF VARCHAR(30) INDEX BY BINARY_INTEGER;
    COLS_IN_PK TEMP_VARCHAR;
    FOREIGN_TABLE TEMP_VARCHAR;
    COLS_IN_PK_LISTAGG VARCHAR2(4000);--1000 КОЛОНОК+ЗАПЯТЫЕ И ПРОБЕЛЫ
    --триггер не мб больше 32к
    TRIGGER_TEXT VARCHAR2(32767);
    --имя зависимой таблицы, имя колонки fk, имя колонки pk
    TYPE FOREIGN_COLUMNS_RECORD IS RECORD (TRG_TAB VARCHAR2(128), COL_B VARCHAR2(30), COL_REF VARCHAR2(30));
    TYPE FOREIGN_COLUMNS_TYPE IS TABLE OF FOREIGN_COLUMNS_RECORD INDEX BY BINARY_INTEGER;
    FOREIGN_COLUMNS FOREIGN_COLUMNS_TYPE;
    
    TYPE COLUMNS_IN_REF_TYPE IS TABLE OF VARCHAR2(30) INDEX BY VARCHAR2(30);
    TYPE TAB_COLUMNS_IN_REF_TYPE IS TABLE OF COLUMNS_IN_REF_TYPE INDEX BY VARCHAR2(30);
    COLUMNS_IN_REF_TABLE TAB_COLUMNS_IN_REF_TYPE;
    
    upd_tab_pk VARCHAR2(4000) := '';
    upd_tab_set VARCHAR2(4000) := '';
    upd_tab_fk VARCHAR2(4000) := '';

  BEGIN
    IF NOT FLAG THEN--ЕСЛИ ЗАХОДИМ НЕ ОТ РОДИТЕЛЬСКОЙ ТАБЛИЦЫ
    --сохраняем имена главных таблиц, выбирая в trg_tab имя первой род. таблицы, если зашли от дочерней или оставляя имя текущей, если зашли от главной(флаг)
    SELECT table_name BULK COLLECT INTO PAR_TAB FROM user_constraints
    WHERE CONSTRAINT_NAME IN (SELECT R_CONSTRAINT_NAME FROM USER_CONSTRAINTS
    where TABLE_NAME=FK_TABLE and CONSTRAINT_TYPE='R' and (sysdate-lAST_CHANGE)*24*60<=3);--смотрим только созданные не 3х минут назад.
    TRG_TAB:=PAR_TAB(1);
    ELSE 
    TRG_TAB:=FK_TABLE;
    END IF;
  
    FOR x IN (SELECT CONSTRAINT_NAME FROM USER_CONSTRAINTS WHERE TABLE_NAME = UPPER(TRG_TAB) AND CONSTRAINT_TYPE IN ('P', 'U')) LOOP
      --увеличивыем счетчик ограничений. Каждая связь-триггер с номером связи.
      CASC_CNT := CASC_CNT + 1;
      /*выбрать зависимую таблицу(имя), имя ее fk ограничения, колонки этого ограничения через запятую, колонки через запятую ограничения pk,
      где имя ограничения одно из тех, что есть в таблице(главной)*/
      REQ := q'[SELECT DISTINCT CON.TABLE_NAME, CON.CONSTRAINT_NAME,
      TRIM(LISTAGG(COL.COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY COL.POSITION) OVER(PARTITION BY CON.CONSTRAINT_NAME)),
      TRIM(LISTAGG(COL1.COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY COL.POSITION) OVER(PARTITION BY CON.CONSTRAINT_NAME))
      FROM USER_CONSTRAINTS CON
      INNER JOIN USER_CONS_COLUMNS COL ON COL.CONSTRAINT_NAME = CON.CONSTRAINT_NAME
      INNER JOIN USER_CONS_COLUMNS COL1 ON COL1.CONSTRAINT_NAME = CON.R_CONSTRAINT_NAME AND COL1.POSITION = COL.POSITION
      WHERE CON.CONSTRAINT_TYPE = 'R' AND (sysdate-con.lAST_CHANGE)*24*60<=3 and CON.R_CONSTRAINT_NAME = ']' || x.CONSTRAINT_NAME || q'[']';
    
      OPEN REF_CURSOR_TEXT FOR REQ;
      FETCH REF_CURSOR_TEXT BULK COLLECT INTO COLUMNS_REFERENCES;
      CLOSE REF_CURSOR_TEXT;
      --если у данного ограничения нет зависимых таблиц, присоединенных менее 3х минут назад, переходим на след. итерацию
      IF COLUMNS_REFERENCES.COUNT = 0 THEN
        CONTINUE;
      END IF;
      
      --откладываем проверку всех fk зависимых таблиц до commit 
      FOR I IN COLUMNS_REFERENCES.FIRST..COLUMNS_REFERENCES.LAST LOOP
        TR_PAK.CALL_TAB(COLUMNS_REFERENCES(I).TRG_TAB):=TRUE;--НЕ ДАЕМ ЗАЦИКЛИТЬСЯ ТРИГГЕРУ
        EXECUTE IMMEDIATE 'ALTER TABLE ' || COLUMNS_REFERENCES(I).TRG_TAB || ' DROP CONSTRAINT ' || COLUMNS_REFERENCES(I).CON_ALTER;
        EXECUTE IMMEDIATE 'ALTER TABLE ' || COLUMNS_REFERENCES(I).TRG_TAB || ' ADD CONSTRAINT ' || COLUMNS_REFERENCES(I).CON_ALTER || ' FOREIGN KEY (' || COLUMNS_REFERENCES(I).COLUMS_LISTAGG_FOREIGN || ') REFERENCES ' || TRG_TAB || '(' || COLUMNS_REFERENCES(I).COLUMS_LISTAGG_REFERENCES || ') DEFERRABLE INITIALLY DEFERRED';
        EXECUTE IMMEDIATE 'SET CONSTRAINT ' || COLUMNS_REFERENCES(I).CON_ALTER || ' DEFERRED';
      END LOOP;
      --очищаем список "запретных таблиц"
       TR_PAK.CALL_TAB.DELETE;
    
      --сохраняем колонки пк(или ограничения) главной таблицы
      REQ := q'[SELECT COL.COLUMN_NAME FROM USER_CONSTRAINTS CON INNER JOIN USER_CONS_COLUMNS COL ON COL.CONSTRAINT_NAME = CON.CONSTRAINT_NAME WHERE CON.CONSTRAINT_NAME = ']' || x.CONSTRAINT_NAME || q'[']';
      
      OPEN REF_CURSOR_TEXT FOR REQ;
      FETCH REF_CURSOR_TEXT BULK COLLECT INTO COLS_IN_PK;
      close REF_CURSOR_TEXT;
      
      COLS_IN_PK_LISTAGG:='';
      --склеиваем колонки пк(уник) для использования в триггере 
      FOR I IN COLS_IN_PK.FIRST..COLS_IN_PK.LAST LOOP
        COLS_IN_PK_LISTAGG := COLS_IN_PK_LISTAGG || COLS_IN_PK(I);
        IF I != COLS_IN_PK.LAST THEN COLS_IN_PK_LISTAGG := COLS_IN_PK_LISTAGG || ', '; END IF;
      END LOOP;
      --начинаем текст триггера 
      TRIGGER_TEXT := 'CREATE OR REPLACE TRIGGER CASCADE_' || TRG_TAB || '_' || CASC_CNT || '
      FOR UPDATE OF ' || COLS_IN_PK_LISTAGG || '  ON ' || TRG_TAB ||  '
      COMPOUND TRIGGER
      TYPE RECS_TYPE IS TABLE OF ' || TRG_TAB ||  '%ROWTYPE;
      NEW_RECS RECS_TYPE;
      OLD_RECS RECS_TYPE;';
      --сохраняем имена зависимых таблиц
      REQ := q'[SELECT CON.TABLE_NAME FROM USER_CONSTRAINTS CON WHERE CON.CONSTRAINT_TYPE = 'R' AND (sysdate-con.lAST_CHANGE)*24*60<=3 and CON.R_CONSTRAINT_NAME = ']' || x.CONSTRAINT_NAME || q'[']';
      OPEN REF_CURSOR_TEXT FOR REQ;
      FETCH REF_CURSOR_TEXT bulk collect into FOREIGN_TABLE;
      CLOSE REF_CURSOR_TEXT;
      --создаем временные таблицы для каждой зависимой таблицы
      FOR I IN FOREIGN_TABLE.FIRST..FOREIGN_TABLE.LAST LOOP
      TRIGGER_TEXT := TRIGGER_TEXT || '
      TYPE FK_RECS_TYPE_'||FOREIGN_TABLE(I)||' IS TABLE OF '||FOREIGN_TABLE(I)||'%ROWTYPE;
      fk_RECS_'||FOREIGN_TABLE(I)||' FK_RECS_TYPE_'||FOREIGN_TABLE(I)||';
      ';
      end LOOP;
      --сохраняем все старые значения
      TRIGGER_TEXT := TRIGGER_TEXT || '
      BEFORE STATEMENT IS
      BEGIN
      SELECT *
      BULK COLLECT INTO OLD_RECS
      FROM ' || TRG_TAB ||';';
      --сохраняем все старые значения хависимых таблиц  
      for I in FOREIGN_TABLE.first..FOREIGN_TABLE.last LOOP
      TRIGGER_TEXT := TRIGGER_TEXT || '
      SELECT *
      bulk collect into FK_RECS_'||FOREIGN_TABLE(I)||'
      FROM ' || FOREIGN_TABLE(I)||';';
      end LOOP;
      
      TRIGGER_TEXT := TRIGGER_TEXT || ' 
      END BEFORE STATEMENT;
      ';
      --получаем список: имя зависимой таблицы, имя колонки главной таблицы ,на которую ссылаются, имя ссылающейся колонки
      REQ := q'[SELECT COL.TABLE_NAME TRG_TAB_NAME, COL1.COLUMN_NAME AS COL_B, COL.COLUMN_NAME AS COL_REF
      FROM USER_CONSTRAINTS CON
      INNER JOIN USER_CONS_COLUMNS COL ON COL.CONSTRAINT_NAME = CON.CONSTRAINT_NAME
      INNER JOIN USER_CONS_COLUMNS COL1 ON COL1.CONSTRAINT_NAME  = CON.R_CONSTRAINT_NAME  AND COL.POSITION = COL1.POSITION
      WHERE CON.CONSTRAINT_TYPE = 'R' and (sysdate-con.lAST_CHANGE)*24*60<=3 AND CON.R_CONSTRAINT_NAME = ']' || x.CONSTRAINT_NAME || q'[']';
      
      OPEN REF_CURSOR_TEXT FOR REQ;
      FETCH REF_CURSOR_TEXT BULK COLLECT INTO FOREIGN_COLUMNS;
      CLOSE REF_CURSOR_TEXT;
      --ЗАПОЛНЯЕМ ВСПОМОГАТЕЛЬНУЮ ТАБЛИЦУ-(имя зависимой таблицы, колонка пк/уник главной таблицы):=колонка fk ссылающаяся
      FOR I IN FOREIGN_COLUMNS.FIRST..FOREIGN_COLUMNS.LAST LOOP
        COLUMNS_IN_REF_TABLE(FOREIGN_COLUMNS(I).TRG_TAB)(FOREIGN_COLUMNS(I).COL_B) := FOREIGN_COLUMNS(I).COL_REF;
      END LOOP;
  
      TRIGGER_TEXT := TRIGGER_TEXT || '
      AFTER STATEMENT IS BEGIN 
      SELECT *
      BULK COLLECT INTO NEW_RECS
      FROM ' || TRG_TAB ||  ';
      ';
      --для каждой таблицы обновляем соответствующие вложенные таблицы, если значения изменялись.
      --идем по всем зависимым таблицам. По каждой строчке вложенной таблицы соответствующей зависимой таблицы
      for I in FOREIGN_TABLE.first..FOREIGN_TABLE.last LOOP
        TRIGGER_TEXT := TRIGGER_TEXT || '
      FOR J IN fk_RECS_'||FOREIGN_TABLE(I)||'.FIRST..fk_RECS_'||FOREIGN_TABLE(I)||'.LAST LOOP
      FOR I IN NEW_RECS.FIRST..NEW_RECS.LAST LOOP
      if ';
      upd_tab_pk := '(';
      upd_tab_set := '';
      upd_tab_fk := ' AND ';
      FOR J IN COLS_IN_PK.FIRST..COLS_IN_PK.LAST LOOP
      upd_tab_pk :=upd_tab_pk ||'OLD_RECS(I).' || COLS_IN_PK(J)||'<>'||'NEW_RECS(I).' || COLS_IN_PK(J);--проверяем, изменилась ли соответствующая колонка pk
      --обновляем, ориентируясь на старые значения главной таблицы
      upd_tab_fk := upd_tab_fk ||'fk_RECS_'||FOREIGN_TABLE(I)||'(j).'||COLUMNS_IN_REF_TABLE(FOREIGN_TABLE(I))(COLS_IN_PK(J)) || ' = OLD_RECS(I).' || COLS_IN_PK(J);
      upd_tab_set := upd_tab_set || 'fk_RECS_'||FOREIGN_TABLE(I)||'(j).'||COLUMNS_IN_REF_TABLE(FOREIGN_TABLE(I))(COLS_IN_PK(J)) || ':= NEW_RECS(I).' || COLS_IN_PK(J)||'; 
      ';
      IF J != COLS_IN_PK.LAST THEN
      upd_tab_pk :=upd_tab_pk||' OR '; 
      upd_tab_fk := upd_tab_fk || ' AND ';
      ELSE
      upd_tab_pk :=upd_tab_pk||')';
      END IF;
      end LOOP;
      TRIGGER_TEXT := TRIGGER_TEXT ||upd_tab_pk||upd_tab_fk|| ' then ' || upd_tab_set||'exit;
      end if;
      END LOOP;
      ';
       --если это рекурсивная связь, меняем все колонки
      if FOREIGN_TABLE(I)=TRG_TAB then 
      for Z in COLS_IN_PK.first..COLS_IN_PK.last LOOP
      TRIGGER_TEXT := TRIGGER_TEXT||'fk_RECS_'||FOREIGN_TABLE(I)||'(J).'||COLS_IN_PK(Z)||':=NEW_RECS(J).' || COLS_IN_PK(Z)||';
      ';
      END LOOP;
      end if;
      TRIGGER_TEXT := TRIGGER_TEXT ||'END LOOP;
      DELETE FROM '||FOREIGN_TABLE(I)||';
      FORALL I IN fk_RECS_'||FOREIGN_TABLE(I)||'.FIRST..fk_RECS_'||FOREIGN_TABLE(I)||'.LAST
      insert into '||FOREIGN_TABLE(I)||' values fk_RECS_'||FOREIGN_TABLE(I)||'(I);';
      END LOOP;
      TRIGGER_TEXT := TRIGGER_TEXT || '
      END AFTER STATEMENT;
      END;';

      --создаем триггер
      EXECUTE IMMEDIATE TRIGGER_TEXT;
      
    END LOOP;
     --для таблицы, при создании которой указывалось несколько связей
      IF NOT FLAG THEN
      FOR X IN 2..PAR_TAB.LAST LOOP
      CR_CAS_TR(PAR_TAB(X),TRUE);
      END LOOP; 
      END IF;
END CR_CAS_TR;
END TR_PAK;
/
--КОД ТРИГГЕРА
create or replace trigger DAMMY_ddl_TRG
after CREATE or ALTER
on schema
begin
  IF ORA_DICT_OBJ_TYPE='TABLE' 
  THEN IF NOT TR_PAK.CALL_TAB.EXISTS(ORA_DICT_OBJ_NAME)--ЕСЛИ ТРИГГЕР ВЫЗВАН НЕ ИЗ ПРОЦЕДУРЫ
        THEN 
        DBMS_SCHEDULER.CREATE_JOB(
        job_name => 'csc'||ORA_DICT_OBJ_NAME||to_char(sysdate,'ddmmyyhh24miss'),
      	JOB_TYPE => 'PLSQL_BLOCK',
        job_action => 'BEGIN TR_PAK.CR_CAS_TR(''' || ora_dict_obj_name || '''); END;',
        start_date      =>       SYSTIMESTAMP + INTERVAL '5' SECOND,
        end_date         =>      SYSTIMESTAMP + INTERVAL '10' SECOND,
        enabled       => TRUE,
        auto_drop => TRUE
      );
      END IF;
  end if;
END DAMMY_DDL_TRG;
/
