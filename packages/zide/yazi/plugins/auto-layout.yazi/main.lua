function Tab:layout()
  local ratio = rt.mgr.ratio
  local constraints

  if self._area.w > 80 then
    constraints = {
      ui.Constraint.Ratio(ratio.parent, ratio.all),
      ui.Constraint.Ratio(ratio.current, ratio.all),
      ui.Constraint.Ratio(ratio.preview, ratio.all),
    }
  elseif self._area.w > 40 then
    constraints = {
      ui.Constraint.Ratio(0, ratio.all),
      ui.Constraint.Ratio(ratio.current + ratio.parent, ratio.all),
      ui.Constraint.Ratio(ratio.preview, ratio.all),
    }
  else
    constraints = {
      ui.Constraint.Ratio(0, ratio.all),
      ui.Constraint.Ratio(ratio.all, ratio.all),
      ui.Constraint.Ratio(0, ratio.all),
    }
  end

  self._chunks = ui.Layout():direction(ui.Layout.HORIZONTAL):constraints(constraints):split(self._area)
end

return {}
