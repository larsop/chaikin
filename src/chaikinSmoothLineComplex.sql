-- A more complecated method that smooth out line by recducing the angle betwwen line segments 
-- for lines between given range and below max_distance. 
-- This a way avoid cutting corners and not adding unessary points.  



DROP FUNCTION IF EXISTS chaikinSmoothLineComplex(_input_line geometry,int,int,numeric,int );
DROP FUNCTION IF EXISTS chaikinSmoothLineComplex(_input_line geometry(LineString),int,int,numeric,int );


CREATE OR REPLACE FUNCTION chaikinSmoothLineComplex(
_input_line geometry(LineString),
_min_degrees int default 90,
_max_degrees int default 270,
_max_distance numeric default 40.0,
_nIterations int default 1 
)
RETURNS geometry(LineString) AS $$
DECLARE
--simplfied_line geometry;
--need_to_fix_index int[];
need_to_fix_index_out int[];

--dump_point_list geometry_dump[];
num_points int;
counter int = 0;
simplfied_line geometry(LineString);

BEGIN

IF (ST_GeometryType(_input_line) != 'ST_LineString' ) THEN
	RAISE EXCEPTION 'Invalid GeometryType(_input_line) %', ST_input_lineetryType(_input_line);
END IF;

 simplfied_line = _input_line;
 

FOR counter IN 1.._nIterations LOOP

 -- loop max 20 times
 IF (counter > 20) THEN
	RAISE EXCEPTION 'To many Iterations %', _nIterations;
 END IF;

WITH 
 rdb_temp_table AS 
 ( SELECT (dp).path[1] As org_index, lead((dp).geom) OVER () AS lead_p, (dp).geom As p1,  lag((dp).geom) OVER () AS lag_p
  FROM (
   SELECT ST_DumpPoints(simplfied_line) as dp
  ) as db
 )    

,
 need_to_fix_index AS 
 (SELECT org_index as index_value from (
  select 
  abs(degrees(azimuth_1-azimuth_2)) as angle, 
  org_index
  --select 100 as angle, 1 as org_index
  from (
   SELECT org_index, 
   ST_Azimuth(p1, lead_p) as azimuth_2, 
   ST_Azimuth(p1, lag_p) as azimuth_1
   FROM 
   rdb_temp_table
   where not ST_Equals(lead_p,p1) and not ST_Equals(p1,lag_p) and
   ST_distance(lead_p, p1) < _max_distance and ST_distance(p1, lag_p) < _max_distance
  ) as r where azimuth_1 is not null and azimuth_2 is not null 
  ) as r where angle <= _min_degrees or angle >= _max_degrees
 )

--select index_value INTO need_to_fix_index_out  FROM need_to_fix_index;

select ST_LineFromMultiPoint(mp) INTO simplfied_line  FROM (
  SELECT ST_Collect(mp) as mp FROM (
  -- how to avoid equal points ??
    SELECT unnest(ARRAY[p1,p1_n,p2_n,lead_p]) as mp FROM (
     SELECT 
     CASE WHEN org_index=1 THEN 
      p1
      ELSE null
     END as p1,
     CASE WHEN p1_n IS NOT NULL THEN 
      p1_n
      ELSE NULLIF(p1, p1_n) 
     END as p1_n,
     CASE WHEN p2_n IS NOT NULL THEN 
      p2_n
      ELSE NULLIF(lead_p, p2_n)
     END as p2_n,
     CASE WHEN org_index=ST_NumPoints(simplfied_line) THEN 
      lead_p
      ELSE null
     END as lead_p
     FROM (
      SELECT 
      org_index,
      p1, 
      CASE WHEN use_p1_n THEN 
       ST_LineInterpolatePoint(lp, 0.25)
       ELSE NULL
      END as p1_n,
      CASE WHEN use_p2_n THEN 
       ST_LineInterpolatePoint(lp, 0.75)
       ELSE NULL
      END as p2_n,
      lead_p 
      FROM (
       SELECT r.*, 
       CASE WHEN use_p1_n or use_p2_n THEN
        ST_MakeLine(p1, lead_p)
        ELSE null 
       END as lp 
       FROM (
        SELECT 
        r.*,
        CASE WHEN exists ( select 1 from need_to_fix_index where r.org_index = index_value OR r.org_index = (index_value-1))  THEN 
         true
         ELSE false
        END as use_p1_n,
        CASE WHEN exists ( select 1 from need_to_fix_index where r.org_index = index_value OR r.org_index = (index_value+1))  THEN 
         true
         ELSE false
        END as use_p2_n
   		FROM rdb_temp_table r
       ) as r
      ) as r
     ) as r
    ) as r
   ) as r
  ) as r
  ;
--  RAISE NOTICE ' simplfied_line  %',  simplfied_line;

--  RAISE NOTICE ' need_to_fix_index  %',  need_to_fix_index_out;

  -- how to avoid this ??
  simplfied_line := ST_RemoveRepeatedPoints(simplfied_line);

  if counter >= _nIterations THEN
   EXIT;
  END IF;
END LOOP;


return simplfied_line;
  
END; 
$$ LANGUAGE plpgsql strict;

\timing
select ST_AsText(chaikinSmoothLineComplex('0102000020E86400000300000000000000F89023410000000070FD584100000000F89023410000000075FD584100000000109123410000000075FD5841'));

SELECT ST_NumPoints(chaikinSmoothLineComplex(ST_Boundary(geo),90,270,10,1)),gid,ST_NumPoints(ST_Boundary(geo)) from org_arstat.ar5_13_flate_s33  
where gid < 3146540 and gid = 3145544  order by gid;
