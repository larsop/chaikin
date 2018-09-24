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
need_to_fix_index int[];
--dump_point_list geometry_dump[];
num_points int;
counter int = 0;
simplfied_line geometry(LineString);
BEGIN

IF (ST_GeometryType(_input_line) != 'ST_LineString' ) THEN
	RAISE EXCEPTION 'Invalid GeometryType(_input_line) %', ST_input_lineetryType(_input_line);
END IF;
 
simplfied_line := _input_line;
	
FOR counter IN 1.._nIterations LOOP

 select array_agg(org_index) into need_to_fix_index from (
  select abs(degrees(azimuth_1-azimuth_2)) as angle,org_index
  --select 100 as angle, 1 as org_index
  from (
   SELECT org_index, 
   ST_Azimuth(p, lead_p) as azimuth_2, 
   ST_Azimuth(p, lag_p) as azimuth_1
   FROM (
    SELECT (dp).path[1] As org_index, lead((dp).geom) OVER () AS lead_p, (dp).geom As p,  lag((dp).geom) OVER () AS lag_p
    FROM (
     SELECT ST_DumpPoints(simplfied_line) as dp
    ) as r
   ) as r where not ST_Equals(lead_p,p) and not ST_Equals(p,lag_p) and
   ST_distance(lead_p, p) < _max_distance and ST_distance(p, lag_p) < _max_distance
  ) as r where azimuth_1 is not null and azimuth_2 is not null 
 ) as r where angle <= _min_degrees or angle >= _max_degrees;

 --RAISE NOTICE 'need_to_fix_index aaa %', need_to_fix_index;
 
 -- if there are no sharp angles use return input as it is
 IF need_to_fix_index IS NULL THEN
  EXIT;
 END IF ;
 
 -- get number of points 
 num_points := ST_NumPoints(simplfied_line);
 
 -- get new simplfied geom
 simplfied_line := ST_LineFromMultiPoint(mp) FROM (
  SELECT ST_Collect(mp) as mp FROM (
    SELECT unnest(ARRAY[p1,p1_n,p2_n,p2]) as mp FROM (
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
      ELSE NULLIF(p2, p2_n)
     END as p2_n,
     CASE WHEN org_index=num_points THEN 
      p2
      ELSE null
     END as p2
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
      p2 
      FROM (
       SELECT r.*, 
       CASE WHEN use_p1_n or use_p2_n THEN
        ST_MakeLine(p1, p2)
        ELSE null 
       END as lp 
       FROM (
        SELECT 
        r.*,
        CASE WHEN org_index = ANY(need_to_fix_index) OR (org_index-1) = ANY(need_to_fix_index) THEN 
         true
         ELSE false
        END as use_p1_n,
        CASE WHEN org_index = ANY(need_to_fix_index) OR (org_index+1) = ANY(need_to_fix_index) THEN 
         true
         ELSE false
        END as use_p2_n
        FROM (
         SELECT  (dp).path[1] As org_index, (dp).geom As p1, lead((dp).geom) OVER () AS p2
         FROM (
          SELECT ST_DumpPoints(simplfied_line) as dp
         ) as r 
        ) as r
       ) as r
      ) as r
     ) as r
    ) as r
   ) as r
  ) as r;

  -- how to avoid this ??
  simplfied_line := ST_RemoveRepeatedPoints(simplfied_line);

  if counter >= _nIterations THEN
   EXIT;
  END IF;
END LOOP;


return simplfied_line;
  
END; 
$$ LANGUAGE plpgsql IMMUTABLE strict;

--select ST_AsText(chaikinSmoothLineComplex('0102000020E86400000300000000000000F89023410000000070FD584100000000F89023410000000075FD584100000000109123410000000075FD5841'));
