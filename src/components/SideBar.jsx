import { Stack, Typography, Box } from '@mui/material';
import { categories } from '../utils/constants';

const SideBar = ({ selectedCategory, setSelectedCategory }) => (
  <Stack
    direction="row"
    sx={{
      overflowY: "auto",
      height: { sx: 'auto', md: '95%' },
      flexDirection: { md: 'column' },
      backgroundColor: { md: 'rgba(26, 0, 0, 0.3)' },
      borderRight: { md: '1px solid var(--border-color)' },
      padding: { md: '16px 0' },
      marginRight: { md: '16px' },
      borderRadius: { xs: 0, md: '12px' },
    }}
  >
    {categories.map((category) => (
      <button
        className='category-btn'
        onClick={() => setSelectedCategory(category.name)}
        style={{
          background: category.name === selectedCategory ? 'var(--hover-color)' : 'transparent',
          color: category.name === selectedCategory ? 'var(--primary-color)' : 'var(--text-primary)'
        }}
        key={category.name}
      >
        <Box 
          component="span" 
          sx={{ 
            color: category.name === selectedCategory ? 'var(--primary-color)' : 'var(--text-secondary)',
            marginRight: '15px',
            display: 'flex',
            alignItems: 'center',
            fontSize: '20px',
            transition: 'color 0.2s ease',
          }}
        >
          {category.icon}
        </Box>
        <Typography 
          component="span"
          variant="body2"
          sx={{
            opacity: category.name === selectedCategory ? '1' : '0.8',
            fontWeight: category.name === selectedCategory ? '500' : '400',
            transition: 'all 0.2s ease',
          }}
        >
          {category.name}
        </Typography>
      </button>
    ))}
  </Stack>
);

export default SideBar;