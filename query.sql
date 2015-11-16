select waiters.id as waiter_id,            waiters.first_name as first_name,            waiters.last_name as last_name,            waiters.personal_id as personal_id,            coalesce(payment_table.total_sum,0) as total_payments,            coalesce(tip_table.tip,0) as total_tips,            coalesce(tip_table.percentage,0) as tip_percent,            coalesce(waiter_table.num_tables,0) as num_tables,            coalesce(payment_table.payments,0) as num_payments,            coalesce(items_table.num_items, 0) as num_items,            coalesce(payment_table.rating, 0) as rating,            coalesce(games_table.count, 0) as num_games,            coalesce(tip_table.total_sum,0) as total_tip_payments,            coalesce(emails_table.num_emails,0) as num_emails,            coalesce(payment_table.turn_time,0) as turn_time,            coalesce(features_table.revenue,0) as game_revenue        from waiters        inner join restaurants on restaurants.id = waiters.restaurant_id        left outer join (            select#Here count(*) is bad for the performance, we should count(some_object) instead of scanning through the whole table#or we could apply "if exists(select * from table)"                count(*) as num_tables            from (                select distinct on(date(last_updated), pos_check_number)                    *#Try not to use select *                from piston_check                where last_updated between %s and %s                and waiter_id = %s                order by date(last_updated), pos_check_number, last_updated desc            ) as moo        ) as waiter_table on true        left outer join(            SELECT                coalesce(sum(total),0) as total_sum,#Here again, we avoid use count(*)                count(*) as payments,                avg(turn_time) as turn_time,                avg(star_rating) as rating            FROM piston_payment            INNER JOIN piston_check ON piston_payment.check_id = piston_check.id            where piston_payment.last_updated between %s and %s#use numeric index instead of text like "cash" in this part of the database design            AND piston_payment.tender_type != 'cash'            and piston_check.waiter_id = %s        ) as payment_table on true           left outer join(            select                coalesce(SUM(tip),0) as tip,                coalesce(sum(total),0) as total_sum,                case when (sum(total) - sum(tip) = 0 or sum(tip) = 0) then 0 else sum(tip) / (sum(total) - sum(tip)) *100 end as percentage# In the last line in "case when (sum(total) - sum(tip) = 0 or sum(tip) = 0)", we could delete the parentheses            from (                SELECT piston_check.waiter_id as waiter_id,                    sum(tip) as tip,                    sum(total) as total                FROM piston_payment                INNER JOIN piston_check ON piston_payment.check_id = piston_check.id                where piston_payment.last_updated between %s and %s#use index instead of text like "cash" in this part of the database design                AND piston_payment.tender_type != 'cash'                and piston_check.waiter_id = %s#Seperate the inside operation of date() as group by should not be overload with stuff                group by date(piston_check.last_updated at time zone 'UTC' - interval '11 hours'), piston_check.pos_check_number, waiter_id            ) as moo# I would try to fit the below line's function into the above subquery            where case when total-tip=0 or tip=0 then 0 else tip end > 0        ) as tip_table on true        left outer join (#Here again, we avoid use count(*)            select count(*) as num_items            from piston_order_item            inner join piston_order on piston_order_item.order_id = piston_order.id            inner join piston_check on piston_order.check_id = piston_check.id            where piston_order.last_updated between %s and %s            and piston_order_item.item_name != 'Presto Games'            and piston_order_item.parent_order_item_id is null            and piston_check.waiter_id = %s        ) as items_table on true        left outer join (            select#Here again, we avoid use count(*)                count (*) as count            from piston_game            inner join piston_check on piston_check.id = piston_game.check_id            where piston_game.last_updated between %s and %s            and piston_check.waiter_id = %s        ) as games_table on true        left outer join(            select count(*) as num_emails            from piston_email            inner join piston_check on check_id = piston_check.id            where piston_email.last_updated between %s and %s            and piston_check.waiter_id = %s            and email ~* '^[A-Za-z0-9._%%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$'            and not email ~* 'elacarte.com$'            and joined_club=true        ) as emails_table on true        left outer join (            select sum(charge) as revenue            from piston_game_feature            inner join piston_game on game_id = piston_game.id            inner join piston_check on piston_check.id = piston_game.check_id            where piston_game.last_updated between %s and %s            and piston_check.waiter_id = %s        ) as features_table on true        where restaurants.code = %s        and waiters.id = %s