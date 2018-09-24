-- A more complecated method that smooth out line by recducing the angle betwwen line segments 
-- for lines between given range and below max_distance. 
-- This a way avoid cutting corners and not adding unessary points.  


CREATE OR REPLACE FUNCTION chaikinSmoothLineComplex(
_geom geometry,
_min_degrees int default 90,
_max_degrees int default 270,
_max_distance numeric default 40.0,
_nIterations int default 5 
)
RETURNS geometry AS $$
DECLARE
--_geom geometry;
sharp_angle_index int[];
--dump_point_list geometry_dump[];
num_points int;
counter int = 0;
BEGIN

-- loop max 5 times, will this ever happen
FOR counter IN 1..5 LOOP

 select array_agg(org_index) into sharp_angle_index from (
  select abs(degrees(azimuth_1-azimuth_2)) as angle,org_index
  --select 100 as angle, 1 as org_index
  from (
   SELECT org_index, 
   ST_Azimuth(p, lead_p) as azimuth_2, 
   ST_Azimuth(p, lag_p) as azimuth_1
   FROM (
    SELECT (dp).path[1] As org_index, lead((dp).geom) OVER () AS lead_p, (dp).geom As p,  lag((dp).geom) OVER () AS lag_p
    FROM (
     SELECT ST_DumpPoints(_geom) as dp
    ) as r
   ) as r where ST_distance(lead_p, p) < _max_distance and ST_distance(p, lag_p) < _max_distance
  ) as r where azimuth_1 is not null and azimuth_2 is not null 
 ) as r where angle <= _min_degrees or angle >= _max_degrees;

 
 -- if there are no sharp angles use return input as it is
 IF sharp_angle_index IS NULL THEN
  EXIT;
 END IF ;

 
 -- get number of points 
 num_points := ST_NumPoints(_geom);
 
 -- assign into varaible
 -- TODO fix this to avoid ST_Dump tywo times
 --SELECT ST_DumpPoints(_geom) into dump_point_list;
  
 -- get sharp angle indexes

 
 -- get new simplfied geom
 _geom := ST_LineFromMultiPoint(mp) FROM (
  SELECT ST_Collect(mp) as mp FROM (
    SELECT unnest(ARRAY[p1,p1_n,p2_n,p2]) as mp FROM (
     SELECT 
     CASE WHEN org_index=1 THEN 
      p1
      ELSE null
     END as p1,
     CASE WHEN p1_n IS NOT NULL THEN 
      p1_n
      ELSE p1
     END as p1_n,
     CASE WHEN p2_n IS NOT NULL THEN 
      p2_n
      ELSE p2
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
        CASE WHEN org_index = ANY(sharp_angle_index) OR (org_index-1) = ANY(sharp_angle_index) THEN 
         true
         ELSE false
        END as use_p1_n,
        CASE WHEN org_index = ANY(sharp_angle_index) OR (org_index+1) = ANY(sharp_angle_index) THEN 
         true
         ELSE false
        END as use_p2_n
        FROM (
         SELECT  (dp).path[1] As org_index, (dp).geom As p1, lead((dp).geom) OVER () AS p2
         FROM (
          SELECT ST_DumpPoints(_geom) as dp
         ) as r 
        ) as r
       ) as r
      ) as r
     ) as r
    ) as r
   ) as r
  ) as r;

  if counter >= _nIterations THEN
   EXIT;
  END IF;
END LOOP;

return _geom;
  
END; 
$$ LANGUAGE plpgsql IMMUTABLE;

--select ST_AsText(chaikinSmoothLineComplex('0102000020E86400000300000000000000F89023410000000070FD584100000000F89023410000000075FD584100000000109123410000000075FD5841'));
